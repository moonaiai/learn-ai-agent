import AppKit

protocol MainViewControllerDelegate: AnyObject {
    func mainDidRequestHide()
    func mainDidTogglePinned(_ pinned: Bool)
}

/// Hosts the top bar and switches between the list (sidebar+editor) and
/// global (card grid) views. Owns the shared notes/categories state.
///
/// Top bar mirrors `src/App.tsx` (.topbar, 40px): title left, icon actions and
/// save-status right. Only its empty area drags the window.
final class MainViewController: NSViewController {

    // Keep the default split compact enough for the complete editor toolbar,
    // including the table actions that appear when the caret enters a table.
    // The panel can still be resized larger by the user.
    static let preferredSidebarWidth: CGFloat = 140
    static let preferredEditorWidth: CGFloat = 530
    static let preferredPanelWidth = preferredSidebarWidth + 1 + preferredEditorWidth

    weak var delegate: MainViewControllerDelegate?

    private let store: NotesStore
    private var notes: [NoteMeta] = []
    private var categories: [Category] = []

    private enum Mode { case global, list }
    // The list view is the default editing surface: it keeps the sidebar and
    // editor visible, while the global view is the card overview.
    private var mode: Mode = .list

    private let editor: NoteEditorController
    private lazy var sidebar = SidebarViewController(store: store)
    private lazy var history = HistoryViewController(store: store)

    init() {
        let s = NotesStore()
        self.store = s
        if Self.shouldUseWebEditor {
            NSLog("[suixinji] editor engine: WKWebView")
            self.editor = WKWebViewEditorViewController(store: s)
        } else {
            NSLog("[suixinji] editor engine: NSTextView")
            self.editor = EditorViewController(store: s)
        }
        super.init(nibName: nil, bundle: nil)
    }

    private static var shouldUseWebEditor: Bool {
        let environment = ProcessInfo.processInfo.environment["SUIXINJI_EDITOR"]?.lowercased()
        let defaults = UserDefaults.standard.string(forKey: "SUIXINJI_EDITOR")?.lowercased()
        let nativeRequested = environment == "native"
            || defaults == "native"
            || CommandLine.arguments.contains("--native-editor")
        // WKWebView is now the default editor. The NSTextView implementation
        // remains available as an explicit rollback path while both engines
        // coexist during the migration.
        return !nativeRequested
    }

    private var currentNoteId: String?
    private var freshBlank = false   // current note is an unsaved blank scratch note
    private var hasInitialized = false  // initial setup runs once in viewDidLayout

    private let container = NSView()
    private let topBar = WindowDragView()
    private let sidebarButton = SidebarToolbarButton()
    private let pinButton = PinToolbarButton()
    private let toggleButton = PillButton(title: "▦")
    private let newButton = PillButton(title: "＋")
    private let newCategoryButton = PillButton(title: "")
    private let notePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let savedLabel = NSTextField(labelWithString: "")
    private var categoryPopover: NSPopover?
    private var sidebarButtonWidthConstraint: NSLayoutConstraint!
    private var toggleButtonTrailingConstraint: NSLayoutConstraint!
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var sidebarDividerWidthConstraint: NSLayoutConstraint!
    private var sidebarHidden = false
    private var listChildrenInstalled = false
    private var historyInstalled = false

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.bg.cgColor

        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = Theme.panel.cgColor
        buildTopBar()

        let topBorder = NSView()
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        topBorder.wantsLayer = true
        topBorder.layer?.backgroundColor = Theme.border.cgColor

        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        view.addSubview(topBorder)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 40),

            topBorder.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            topBorder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),

            container.topAnchor.constraint(equalTo: topBorder.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        editor.delegate = self
        sidebar.delegate = self
        history.delegate = self
        // Initial mode/data setup is deferred to viewDidLayout. viewDidLoad runs
        // before PanelController assigns the 760×520 content frame, so the view
        // is still .zero here — building the split / calling setPosition(200,…)
        // on a 0-width canvas collapses the panes to 0 and the editor never
        // shows. viewDidLayout fires against a real frame.
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if !hasInitialized {
            hasInitialized = true
            switchToMode(.list)
            refreshAll()
            openDefaultNoteAfterRefresh()
        }
    }

    // MARK: - Top bar (App.css .topbar)

    private func buildTopBar() {
        let titleLabel = NSTextField(labelWithString: "随心记")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Theme.titleFont
        titleLabel.textColor = Theme.text

        savedLabel.translatesAutoresizingMaskIntoConstraints = false
        savedLabel.font = Theme.smallFont
        savedLabel.textColor = Theme.textDim
        savedLabel.isBezeled = false
        savedLabel.drawsBackground = false
        savedLabel.isSelectable = false
        savedLabel.alignment = .right

        sidebarButton.target = self
        sidebarButton.action = #selector(toggleSidebar)
        sidebarButton.translatesAutoresizingMaskIntoConstraints = false
        pinButton.translatesAutoresizingMaskIntoConstraints = false
        pinButton.setPinned(false)
        pinButton.onClick = { [weak self] in self?.togglePinned() }
        newButton.setSymbol("plus", accessibilityDescription: "新建笔记")
        toggleButton.setSymbol("square.grid.2x2", accessibilityDescription: "切换视图")
        toggleButton.onClick = { [weak self] in self?.toggleMode() }
        toggleButton.toolTip = "切换视图"
        newButton.onClick = { [weak self] in self?.handleNewNote() }
        newButton.toolTip = "新建笔记"
        newCategoryButton.setSymbol("folder.badge.plus", accessibilityDescription: "新建类别")
        newCategoryButton.onClick = { [weak self] in self?.toggleCategoryPopover() }
        newCategoryButton.toolTip = "新建类别"

        notePicker.translatesAutoresizingMaskIntoConstraints = false
        notePicker.isBordered = false
        notePicker.bezelStyle = .inline
        notePicker.font = Theme.titleFont
        notePicker.alignment = .left
        notePicker.contentTintColor = Theme.textDim
        notePicker.toolTip = "切换笔记"
        notePicker.setAccessibilityLabel("选择笔记")
        notePicker.target = self
        notePicker.action = #selector(notePickerChanged(_:))
        // Keep the popup compact in the top bar. Long note titles are clipped
        // by the popup cell instead of expanding into the action area.
        notePicker.cell?.lineBreakMode = .byTruncatingTail
        notePicker.cell?.usesSingleLineMode = true

        // PillButton is an NSView that sizes itself from its internal label's
        // edge constraints. It MUST opt into Auto Layout — otherwise AppKit
        // auto-generates constraints from its .zero frame, which conflict with
        // the centerY/trailing anchors below and collapse the button to 0×0
        // (the previous regression: topbar buttons invisible).
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        newButton.translatesAutoresizingMaskIntoConstraints = false
        newCategoryButton.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        toggleButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        newButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        newButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        newCategoryButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        newCategoryButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        [sidebarButton, pinButton, titleLabel, notePicker, newCategoryButton, newButton, toggleButton, savedLabel].forEach {
            topBar.addSubview($0)
        }

        sidebarButtonWidthConstraint = sidebarButton.widthAnchor.constraint(equalToConstant: 28)
        toggleButtonTrailingConstraint = toggleButton.trailingAnchor.constraint(equalTo: sidebarButton.leadingAnchor,
                                                                                 constant: -4)

        NSLayoutConstraint.activate([
            sidebarButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            sidebarButton.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -4),
            sidebarButtonWidthConstraint,
            sidebarButton.heightAnchor.constraint(equalToConstant: 28),

            pinButton.trailingAnchor.constraint(equalTo: savedLabel.leadingAnchor, constant: -4),
            pinButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 28),
            pinButton.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            notePicker.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            notePicker.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            notePicker.widthAnchor.constraint(equalToConstant: 180),
            notePicker.heightAnchor.constraint(equalToConstant: 26),

            savedLabel.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -14),
            savedLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            toggleButtonTrailingConstraint,
            toggleButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            newButton.trailingAnchor.constraint(equalTo: toggleButton.leadingAnchor, constant: -4),
            newButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            newCategoryButton.trailingAnchor.constraint(equalTo: newButton.leadingAnchor, constant: -4),
            newCategoryButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
        ])

        notePicker.isHidden = true
    }

    private func toggleMode() {
        switchToMode(mode == .global ? .list : .global)
    }

    @objc private func toggleSidebar() {
        sidebarHidden.toggle()
        applySidebarVisibility()
    }

    @objc private func notePickerChanged(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String,
              id != currentNoteId else { return }
        openNote(id)
    }

    private func toggleCategoryPopover() {
        if let categoryPopover, categoryPopover.isShown {
            categoryPopover.performClose(nil)
            return
        }

        let content = NewCategoryPopoverViewController(store: store) { [weak self] in
            self?.handleMutate()
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = content
        popover.contentSize = NSSize(width: 224, height: 62)
        categoryPopover = popover
        popover.show(relativeTo: newCategoryButton.bounds,
                     of: newCategoryButton,
                     preferredEdge: .maxY)
    }

    private func togglePinned() {
        pinButton.setPinned(!pinButton.isPinned)
        delegate?.mainDidTogglePinned(pinButton.isPinned)
    }

    // MARK: - Mode switching

    private func installListChildrenIfNeeded() {
        guard !listChildrenInstalled else { return }
        listChildrenInstalled = true

        sidebar.view.translatesAutoresizingMaskIntoConstraints = false
        editor.view.translatesAutoresizingMaskIntoConstraints = false
        let splitDivider = NSView()
        splitDivider.translatesAutoresizingMaskIntoConstraints = false
        splitDivider.wantsLayer = true
        splitDivider.layer?.backgroundColor = Theme.border.cgColor
        container.addSubview(sidebar.view)
        container.addSubview(splitDivider)
        container.addSubview(editor.view)

        sidebarWidthConstraint = sidebar.view.widthAnchor.constraint(equalToConstant: Self.preferredSidebarWidth)
        sidebarDividerWidthConstraint = splitDivider.widthAnchor.constraint(equalToConstant: 1)

        NSLayoutConstraint.activate([
            sidebar.view.topAnchor.constraint(equalTo: container.topAnchor),
            sidebar.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebar.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sidebarWidthConstraint,
            sidebar.view.trailingAnchor.constraint(equalTo: splitDivider.leadingAnchor),

            splitDivider.topAnchor.constraint(equalTo: container.topAnchor),
            splitDivider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebarDividerWidthConstraint,

            editor.view.topAnchor.constraint(equalTo: container.topAnchor),
            editor.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            editor.view.leadingAnchor.constraint(equalTo: splitDivider.trailingAnchor),
            editor.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    private func installHistoryIfNeeded() {
        guard !historyInstalled else { return }
        historyInstalled = true
        history.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(history.view)
        NSLayoutConstraint.activate([
            history.view.topAnchor.constraint(equalTo: container.topAnchor),
            history.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            history.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            history.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    private func switchToMode(_ m: Mode) {
        mode = m
        // Keep all child views installed and switch visibility instead of
        // removing NSViews from the hierarchy. AppKit 26 can invalidate a
        // borderless panel's view subtree while it is being reactivated; the
        // old remove/re-add path crashed in NSView.removeFromSuperview when
        // toggling back from the global view.
        installListChildrenIfNeeded()
        toggleButton.setSymbol(m == .global ? "list.bullet" : "square.grid.2x2",
                               accessibilityDescription: "切换视图")

        let listMode = m == .list
        if !listMode { installHistoryIfNeeded() }
        sidebarButton.setCollapsed(sidebarHidden)
        applySidebarVisibility(listMode: listMode)
        editor.view.isHidden = !listMode
        if historyInstalled { history.view.isHidden = listMode }
    }

    private func applySidebarVisibility(listMode: Bool? = nil) {
        let isListMode = listMode ?? (mode == .list)
        sidebarWidthConstraint?.constant = sidebarHidden ? 0 : Self.preferredSidebarWidth
        sidebarDividerWidthConstraint?.constant = sidebarHidden ? 0 : 1
        sidebar.view.isHidden = !isListMode || sidebarHidden
        sidebarButton.setCollapsed(sidebarHidden)
        sidebarButton.isHidden = !isListMode
        sidebarButtonWidthConstraint?.constant = isListMode ? 28 : 0
        toggleButtonTrailingConstraint?.constant = isListMode ? -4 : 0
        notePicker.isHidden = !(isListMode && sidebarHidden)
        view.layoutSubtreeIfNeeded()
    }

    // MARK: - Data

    func refreshAll() {
        notes = store.listNotes()
        categories = store.listCategories()
        refreshChildren()
    }

    private func refreshChildren() {
        sidebar.reload(notes: notes, categories: categories)
        history.reload(notes: notes, categories: categories)
        reloadNotePicker()
        sidebar.selectNote(currentNoteId)
    }

    /// Rebuild the compact top-bar note switcher from the same sorted list used
    /// by the sidebar. A scratch note is represented by the non-actionable
    /// placeholder until its first save creates a real NoteMeta entry.
    private func reloadNotePicker() {
        notePicker.removeAllItems()
        notePicker.addItem(withTitle: "新笔记")
        notePicker.item(at: 0)?.representedObject = nil

        for note in notes {
            let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = title.isEmpty ? "无标题" : title
            let item = NSMenuItem(title: note.icon + "  " + displayTitle,
                                  action: nil,
                                  keyEquivalent: "")
            item.representedObject = note.id
            notePicker.menu?.addItem(item)
        }

        if let currentNoteId,
           let index = notePicker.menu?.items.firstIndex(where: {
               ($0.representedObject as? String) == currentNoteId
           }) {
            notePicker.selectItem(at: index)
        } else {
            notePicker.selectItem(at: 0)
        }
    }

    // MARK: - Note lifecycle

    /// Called when the panel is shown: enter the default list editor and ensure
    /// a fresh blank note is ready.
    func onShow() {
        switchToMode(.list)
        refreshAll()
        openDefaultNoteAfterRefresh()
        DispatchQueue.main.async { self.editor.focus() }
    }

    /// The panel is a quick-entry surface. On every show, open the newest
    /// existing note; only an empty store gets a new scratch note.
    private func openDefaultNoteAfterRefresh() {
        if let first = notes.first {
            openNote(first.id)
        } else {
            startFreshBlankNote()
        }
    }

    /// Flush the current note before the panel hides (autosave on hide).
    func flushBeforeHide() {
        editor.flush(userInitiated: false)
    }

    /// Save immediately (Cmd+S), regardless of which control has focus.
    func saveNow() {
        editor.flush(userInitiated: true)
    }

    /// Create a fresh note from a window-level shortcut, regardless of which
    /// child control currently has focus.
    func createNewNote() {
        handleNewNote()
    }

    private func startFreshBlankNote() {
        editor.newNote()
        currentNoteId = editor.currentNoteId
        freshBlank = true
        reloadNotePicker()
        sidebar.selectNote(nil)
    }

    private func handleNewNote() {
        // A scratch note becomes a real note as soon as it has pending edits,
        // even if the 3-second autosave has not fired yet.
        if freshBlank && !editor.hasUnsavedChanges {
            switchToMode(.list)
            editor.focus()
            return
        }
        editor.flush(userInitiated: false)
        startFreshBlankNote()
        switchToMode(.list)
        editor.focus()
    }

    private func openNote(_ id: String) {
        editor.flush(userInitiated: false)
        editor.openNote(id: id)
        currentNoteId = id
        freshBlank = false
        reloadNotePicker()
        switchToMode(.list)
        editor.focus()
        sidebar.selectNote(id)
    }

    // MARK: - Category mutations from children

    private func handleMutate() {
        let prev = currentNoteId
        refreshAll()
        if let p = prev { currentNoteId = p; sidebar.selectNote(p) }
    }
}

// MARK: - Editor delegate

extension MainViewController: EditorViewControllerDelegate {
    func noteMetaDidChange(_ noteId: String) {
        let prev = currentNoteId
        refreshAll()
        if let p = prev { currentNoteId = p; sidebar.selectNote(p) }
        freshBlank = false
    }
    func noteWasDeleted(_ noteId: String) {
        if currentNoteId == noteId {
            startFreshBlankNote()
        }
        refreshAll()
    }
    func editorRequestsHide() {
        delegate?.mainDidRequestHide()
    }

    func editorDidConsumeEscape() -> Bool {
        editor.handleEscape()
    }

    func editorDidConsumePaste() -> Bool {
        editor.handlePaste()
    }
    func editorSaveStatus(_ text: String) {
        let status = text.trimmingCharacters(in: .whitespacesAndNewlines)
        savedLabel.toolTip = status.isEmpty ? nil : status
        savedLabel.setAccessibilityValue(status.isEmpty ? nil : status)
        if status.isEmpty {
            savedLabel.stringValue = ""
            savedLabel.textColor = Theme.textDim
        } else if status == "未保存" {
            savedLabel.stringValue = "●"
            savedLabel.textColor = Theme.accent
        } else {
            // Keep the exact timestamp available on hover while the top bar
            // only reserves space for a compact status mark.
            savedLabel.stringValue = "✓"
            savedLabel.textColor = Theme.textDim
        }
    }
}

// MARK: - Sidebar / history delegates

extension MainViewController: SidebarViewControllerDelegate {
    func sidebarDidSelectNote(_ id: String) { openNote(id) }
    func sidebarDidMutate() { handleMutate() }
}

extension MainViewController: HistoryViewControllerDelegate {
    func historyDidSelectNote(_ id: String) { openNote(id) }
    func historyDidDeleteNote(_ id: String) {
        store.deleteNote(id: id)
        if currentNoteId == id {
            startFreshBlankNote()
        }
        refreshAll()
    }
    func historyDidMutate() { handleMutate() }
}

// MARK: - Sidebar toolbar button

/// Borderless native sidebar control. Keeping it in the top bar follows the
/// macOS convention and leaves the split divider visually clean.
final class SidebarToolbarButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .inline
        focusRingType = .none
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = Theme.textDim
        setCollapsed(false)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setCollapsed(_ collapsed: Bool) {
        let description = collapsed ? "显示左侧栏" : "隐藏左侧栏"
        if let symbol = NSImage(systemSymbolName: collapsed ? "sidebar.right" : "sidebar.left",
                                accessibilityDescription: description) {
            symbol.isTemplate = true
            image = symbol.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        }
        toolTip = collapsed ? "显示左侧栏" : "隐藏左侧栏"
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        contentTintColor = Theme.accent
    }

    override func mouseExited(with event: NSEvent) {
        contentTintColor = Theme.textDim
    }
}

/// Borderless pin control for the floating panel. It stays in the top bar so
/// the panel's fixed state is visible without adding another settings surface.
final class PinToolbarButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?
    private(set) var isPinned = false
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .inline
        focusRingType = .none
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = Theme.textDim
        target = self
        action = #selector(tap)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        let symbol = pinned ? "pin.fill" : "pin"
        if let image = NSImage(systemSymbolName: symbol,
                               accessibilityDescription: pinned ? "取消固定浮窗" : "固定浮窗") {
            image.isTemplate = true
            self.image = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        }
        toolTip = pinned ? "取消固定浮窗" : "固定浮窗"
        setAccessibilityLabel(toolTip ?? "固定浮窗")
    }

    @objc private func tap() { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        contentTintColor = Theme.accent
    }

    override func mouseExited(with event: NSEvent) {
        contentTintColor = Theme.textDim
    }
}

// MARK: - Pill button (App.css .view-toggle)

final class PillButton: NSView {
    private let label = NSTextField(labelWithString: "")
    private let symbolView = NSImageView()
    var onClick: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 0
        layer?.backgroundColor = NSColor.clear.cgColor

        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = Theme.textDim
        label.stringValue = title
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        addSubview(label)
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.contentTintColor = Theme.textDim
        addSubview(symbolView)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 16),
            symbolView.heightAnchor.constraint(equalToConstant: 16),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(tap))
        addGestureRecognizer(click)
        installHoverTracker(on: self) { [weak self] h in
            self?.layer?.backgroundColor = NSColor.clear.cgColor
            self?.label.textColor = h ? Theme.accent : Theme.textDim
            self?.symbolView.contentTintColor = h ? Theme.accent : Theme.textDim
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    func setSymbol(_ symbolName: String, accessibilityDescription: String) {
        guard let symbol = NSImage(systemSymbolName: symbolName,
                                   accessibilityDescription: accessibilityDescription) else { return }
        symbol.isTemplate = true
        symbolView.image = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        setAccessibilityLabel(accessibilityDescription)
    }

    @objc private func tap() { onClick?() }
}

/// Compact transient editor used by the top-bar new-category button.
/// Keeping the input out of the top bar prevents the operation area from
/// expanding when a category is being created.
final class NewCategoryPopoverViewController: NSViewController {
    private let store: NotesStore
    private let onCreated: () -> Void
    private let input = NSTextField()
    private let saveButton = NSButton(frame: .zero)
    private let cancelButton = NSButton(frame: .zero)

    init(store: NotesStore, onCreated: @escaping () -> Void) {
        self.store = store
        self.onCreated = onCreated
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.elevated.cgColor

        input.translatesAutoresizingMaskIntoConstraints = false
        input.placeholderString = "类别名称"
        input.font = Theme.bodyFont
        input.backgroundColor = Theme.bg
        input.textColor = Theme.text
        input.bezelStyle = .roundedBezel
        input.focusRingType = .none
        input.target = self
        input.action = #selector(commit)
        input.setContentHuggingPriority(.defaultLow, for: .horizontal)
        input.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureIconButton(saveButton,
                            symbol: "checkmark",
                            description: "保存类别",
                            tint: Theme.accent,
                            action: #selector(commit))
        configureIconButton(cancelButton,
                            symbol: "xmark",
                            description: "取消",
                            tint: Theme.textDim,
                            action: #selector(cancel))

        let row = NSStackView(views: [input, saveButton, cancelButton])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        root.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 30),
            input.widthAnchor.constraint(greaterThanOrEqualToConstant: 132),
            saveButton.widthAnchor.constraint(equalToConstant: 24),
            saveButton.heightAnchor.constraint(equalToConstant: 24),
            cancelButton.widthAnchor.constraint(equalToConstant: 24),
            cancelButton.heightAnchor.constraint(equalToConstant: 24),
        ])
        self.view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.input)
        }
    }

    private func configureIconButton(_ button: NSButton,
                                     symbol: String,
                                     description: String,
                                     tint: NSColor,
                                     action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .inline
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = tint
        button.toolTip = description
        button.setAccessibilityLabel(description)
        button.image = NSImage(systemSymbolName: symbol,
                                accessibilityDescription: description)?.withSymbolConfiguration(
                                    NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        button.target = self
        button.action = action
    }

    @objc private func commit() {
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            NSSound.beep()
            view.window?.makeFirstResponder(input)
            return
        }
        store.upsertCategory(id: "", name: name)
        onCreated()
        view.window?.performClose(nil)
    }

    @objc private func cancel() {
        view.window?.performClose(nil)
    }
}
