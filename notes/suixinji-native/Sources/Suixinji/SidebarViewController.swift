import AppKit

protocol SidebarViewControllerDelegate: AnyObject {
    func sidebarDidSelectNote(_ id: String)
    func sidebarDidMutate()   // notes/categories changed externally → reload
}

/// Left pane of the list view (App.css `.split-list`, 200px).
///
/// Renders notes grouped by category as a flat vertical stack — mirroring
/// `src/views/SplitEditor.tsx`:
/// - category sections with a header (name + count + hover rename ✏ / delete 🗑),
///   未归类 pinned last with no edit affordances,
/// - note rows: icon + (title + mtime) two-line layout, hover delete × with an
///   inline 删/✗ confirm, active row highlighted with an accent left bar,
/// - drag a note row onto a category section to re-categorize,
/// - the ＋ 新类别 creator lives in the top operation bar.
final class SidebarViewController: NSViewController {

    weak var delegate: SidebarViewControllerDelegate?

    private let store: NotesStore
    private var notes: [NoteMeta] = []
    private var categories: [Category] = []

    fileprivate struct Section { let category: Category?; var notes: [NoteMeta] }
    fileprivate var sections: [Section] = []

    static let noteIdPBType = NSPasteboard.PasteboardType("com.suixinji.noteid")

    private let stack = SidebarStackView()
    private var currentNoteId: String?

    init(store: NotesStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.panel.cgColor

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        // Keep the list naturally scrollable while removing the scrollbar from
        // the layout and visual surface.
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.wantsLayer = true

        scroll.documentView = stack
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        self.view = view
    }

    func reload(notes: [NoteMeta], categories: [Category]) {
        self.notes = notes
        self.categories = categories
        rebuildSections()
        rebuildList()
    }

    func selectNote(_ id: String?) {
        currentNoteId = id
        markActiveAcrossStack()
    }

    private func markActiveAcrossStack() {
        for case let sec as CategorySectionView in stack.arrangedSubviews {
            sec.setActiveNote(currentNoteId)
        }
    }

    private func rebuildSections() {
        var byCat: [String: [NoteMeta]] = [:]
        var uncat: [NoteMeta] = []
        let known = Set(categories.map { $0.id })
        for n in notes {
            if n.category.isEmpty || !known.contains(n.category) { uncat.append(n) }
            else { byCat[n.category, default: []].append(n) }
        }
        sections = categories.map { Section(category: $0, notes: byCat[$0.id] ?? []) }
        if !uncat.isEmpty { sections.append(Section(category: nil, notes: uncat)) }
    }

    private func rebuildList() {
        // Detach arranged subviews from NSStackView before releasing them.
        // Calling removeFromSuperview directly leaves AppKit 26's stack-view
        // bookkeeping half-updated and can crash with EXC_BAD_ACCESS when the
        // panel is shown again or a note is saved.
        for subview in stack.arrangedSubviews {
            stack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        for sec in sections {
            let section = CategorySectionView(store: store, section: sec) { [weak self] event in
                guard let self = self else { return }
                switch event {
                case .selectNote(let id):
                    self.currentNoteId = id
                    self.markActiveAcrossStack()
                    self.delegate?.sidebarDidSelectNote(id)
                case .deleteNote(let id):
                    self.store.deleteNote(id: id)
                    self.delegate?.sidebarDidMutate()
                case .mutate:
                    self.delegate?.sidebarDidMutate()
                }
            }
            section.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            section.setActiveNote(currentNoteId)
        }
    }
}

/// NSScrollView lays out a non-flipped document view from its bottom edge.
/// Flipping the stack makes the first category/note row stay at the top when
/// the list is shorter than the viewport.
private final class SidebarStackView: NSStackView {
    override var isFlipped: Bool { true }
}

// MARK: - Section (header + note rows, drop target)

final class CategorySectionView: NSView {
    enum Event {
        case selectNote(String)
        case deleteNote(String)
        case mutate
    }

    private let store: NotesStore
    private let section: SidebarViewController.Section
    private let onEvent: (Event) -> Void
    private let content = NSStackView()
    private var isDragOver = false {
        didSet {
            needsDisplay = true
            layer?.backgroundColor = isDragOver ? Theme.accentSoft.cgColor : NSColor.clear.cgColor
        }
    }

    fileprivate init(store: NotesStore, section: SidebarViewController.Section, onEvent: @escaping (Event) -> Void) {
        self.store = store
        self.section = section
        self.onEvent = onEvent
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.widthAnchor.constraint(equalTo: widthAnchor),
        ])

        let header = CategoryHeaderView(category: section.category, count: section.notes.count) { [weak self] event in
            guard let self = self else { return }
            switch event {
            case .rename(let name):
                if let c = self.section.category { self.store.upsertCategory(id: c.id, name: name) }
                self.onEvent(.mutate)
            case .delete:
                if let c = self.section.category {
                    self.store.deleteCategory(id: c.id)
                    self.onEvent(.mutate)
                }
            }
        }
        content.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        for note in section.notes {
            let row = NoteRowView(note: note) { [weak self] event in
                guard let self = self else { return }
                switch event {
                case .select(let id): self.onEvent(.selectNote(id))
                case .delete(let id): self.onEvent(.deleteNote(id))
                }
            }
            content.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        registerForDraggedTypes([SidebarViewController.noteIdPBType])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setActiveNote(_ id: String?) {
        for case let row as NoteRowView in content.arrangedSubviews {
            row.setActive(row.noteId == id)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isDragOver {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
            Theme.accentSoft.setFill()
            path.fill()
            Theme.accent.setStroke()
            path.lineWidth = 1
            let dash: [CGFloat] = [4, 3]
            path.setLineDash(dash, count: 2, phase: 0)
            path.stroke()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragOver = true
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragOver = false
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragOver = false
        guard let id = sender.draggingPasteboard.string(forType: SidebarViewController.noteIdPBType) else { return false }
        let targetCategoryId = section.category?.id ?? ""
        store.setNoteCategory(noteId: id, categoryId: targetCategoryId)
        onEvent(.mutate)
        return true
    }
}

// MARK: - Category header (name + count + hover rename/delete)

final class CategoryHeaderView: NSView {
    enum Event { case rename(String); case delete }

    private let category: Category?
    private let onEvent: (Event) -> Void
    private var mode: Mode = .view { didSet { rebuild() } }
    private enum Mode { case view, rename, confirm }

    private let nameField = NSTextField(labelWithString: "")
    private let countField = NSTextField(labelWithString: "")
    private let delBtn = SmallIconButton(title: "×", tooltip: "删除类别(其中笔记移至未归类)")
    private var nameInput: NSTextField?

    init(category: Category?, count: Int, onEvent: @escaping (Event) -> Void) {
        self.category = category
        self.onEvent = onEvent
        super.init(frame: .zero)
        wantsLayer = true
        nameField.font = Theme.smallBoldFont
        nameField.textColor = (category == nil) ? Theme.textDim : Theme.textDim
        nameField.stringValue = category?.name ?? "未归类"
        countField.font = Theme.smallFont
        countField.textColor = Theme.textDim
        countField.alphaValue = 0.6
        countField.stringValue = "\(count)"

        delBtn.onActivate = { [weak self] in self?.mode = .confirm }
        delBtn.isHidden = (category == nil)

        // Renaming is intentionally a quiet interaction: double-click the
        // category name instead of keeping a permanent edit icon in the row.
        let renameGesture = NSClickGestureRecognizer(target: self,
                                                     action: #selector(handleNameDoubleClick))
        renameGesture.numberOfClicksRequired = 2
        nameField.addGestureRecognizer(renameGesture)

        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        if mode == .view {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            row.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 4, right: 8)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addArrangedSubview(nameField)
            row.addArrangedSubview(countField)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(spacer)
            row.addArrangedSubview(delBtn)
            addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: topAnchor),
                row.bottomAnchor.constraint(equalTo: bottomAnchor),
                row.leadingAnchor.constraint(equalTo: leadingAnchor),
                row.trailingAnchor.constraint(equalTo: trailingAnchor),
                row.heightAnchor.constraint(equalToConstant: 26),
            ])
            // Only show the delete affordance while the pointer is over this
            // category row; the rest of the header stays visually clean.
            installHoverTracker(on: self) { [weak self] hovered in
                self?.delBtn.alphaValue = hovered ? 1.0 : 0.0
            }
            delBtn.alphaValue = 0
        } else if mode == .rename {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 4
            row.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 4, right: 8)
            row.translatesAutoresizingMaskIntoConstraints = false
            let input = NSTextField()
            input.stringValue = category?.name ?? ""
            input.font = Theme.smallFont
            input.backgroundColor = Theme.bg
            input.textColor = Theme.text
            input.bezelStyle = .roundedBezel
            input.focusRingType = .none
            input.target = self
            input.action = #selector(commitRename)
            input.translatesAutoresizingMaskIntoConstraints = false
            nameInput = input
            let ok = MiniButton(title: "✓", filled: true) { [weak self] in self?.commitRename() }
            let cancel = MiniButton(title: "✗", filled: false) { [weak self] in self?.mode = .view }
            row.addArrangedSubview(input)
            row.addArrangedSubview(ok)
            row.addArrangedSubview(cancel)
            addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: topAnchor),
                row.bottomAnchor.constraint(equalTo: bottomAnchor),
                row.leadingAnchor.constraint(equalTo: leadingAnchor),
                row.trailingAnchor.constraint(equalTo: trailingAnchor),
                row.heightAnchor.constraint(equalToConstant: 28),
            ])
            window?.makeFirstResponder(input)
        } else {
            // confirm delete
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 4
            row.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 4, right: 8)
            row.translatesAutoresizingMaskIntoConstraints = false
            let text = NSTextField(labelWithString: "删除「\(category?.name ?? "")」?")
            text.font = Theme.smallFont
            text.textColor = Theme.text
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let del = MiniButton(title: "删除", danger: true) { [weak self] in
                self?.onEvent(.delete)
                self?.mode = .view
            }
            let cancel = MiniButton(title: "取消", filled: false) { [weak self] in self?.mode = .view }
            row.addArrangedSubview(text)
            row.addArrangedSubview(spacer)
            row.addArrangedSubview(del)
            row.addArrangedSubview(cancel)
            addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: topAnchor),
                row.bottomAnchor.constraint(equalTo: bottomAnchor),
                row.leadingAnchor.constraint(equalTo: leadingAnchor),
                row.trailingAnchor.constraint(equalTo: trailingAnchor),
                row.heightAnchor.constraint(equalToConstant: 28),
            ])
        }
    }

    @objc private func commitRename() {
        let name = (nameInput?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { onEvent(.rename(name)) }
        mode = .view
    }

    private func enterRename() { mode = .rename }

    @objc private func handleNameDoubleClick() {
        guard category != nil else { return }
        enterRename()
    }
}

// MARK: - Note row (icon + title + time + hover delete, drag source)

final class NoteRowView: NSView {
    enum Event { case select(String); case delete(String) }

    let noteId: String
    private let onEvent: (Event) -> Void
    private var confirming = false { didSet { rebuild() } }
    private var isActive = false { didSet { needsDisplay = true } }
    private var isHover = false { didSet { needsDisplay = true; controlsHidden = !(isHover || isActive || confirming) } }

    private let iconLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let deleteBtn = SmallIconButton(title: "×", tooltip: "删除笔记")
    private let controls = NSStackView()

    init(note: NoteMeta, onEvent: @escaping (Event) -> Void) {
        self.noteId = note.id
        self.onEvent = onEvent
        super.init(frame: .zero)
        wantsLayer = true

        iconLabel.font = NSFont.systemFont(ofSize: 15)
        iconLabel.stringValue = note.icon
        iconLabel.textColor = Theme.text

        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = Theme.text
        titleLabel.usesSingleLineMode = true
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.wraps = false
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.stringValue = note.title.isEmpty ? "无标题" : note.title
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        timeLabel.font = Theme.smallFont
        timeLabel.textColor = Theme.textDim
        timeLabel.stringValue = formatTime(note.mtime)
        timeLabel.lineBreakMode = .byTruncatingTail

        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 1
        body.translatesAutoresizingMaskIntoConstraints = false
        body.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        body.addArrangedSubview(titleLabel)
        body.addArrangedSubview(timeLabel)

        controls.orientation = .horizontal
        controls.spacing = 3
        controls.translatesAutoresizingMaskIntoConstraints = false
        deleteBtn.font = NSFont.systemFont(ofSize: 15)
        deleteBtn.onActivate = { [weak self] in self?.confirming = true }

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(iconLabel)
        row.addArrangedSubview(body)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        controls.addArrangedSubview(deleteBtn)
        row.addArrangedSubview(controls)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.heightAnchor.constraint(equalToConstant: 44),
        ])
        rebuild()

        installHoverTracker(on: self) { [weak self] hovered in
            self?.isHover = hovered
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private var controlsHidden = true {
        didSet { controls.isHidden = controlsHidden }
    }

    func setActive(_ active: Bool) {
        isActive = active
        controlsHidden = !(isHover || isActive || confirming)
    }

    private func rebuild() {
        controls.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if confirming {
            let yes = MiniButton(title: "删", danger: true) { [weak self] in
                guard let self = self else { return }
                self.onEvent(.delete(self.noteId))
            }
            let no = MiniButton(title: "✗", filled: false) { [weak self] in self?.confirming = false }
            controls.addArrangedSubview(yes)
            controls.addArrangedSubview(no)
            controls.isHidden = false
        } else {
            controls.addArrangedSubview(deleteBtn)
            controls.isHidden = !(isHover || isActive)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Active: accent-soft fill + 2px accent left bar (App.css .split-item.active).
        if isActive {
            Theme.accentSoft.setFill()
            NSBezierPath(rect: bounds).fill()
            let bar = NSRect(x: 0, y: 0, width: 2, height: bounds.height)
            Theme.accent.setFill()
            NSBezierPath(rect: bar).fill()
        } else if isHover {
            Theme.elevated.setFill()
            NSBezierPath(rect: bounds).fill()
        }
    }

    // MARK: - Click vs drag (5px threshold, mirrors SplitEditor pointer logic)

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        let start = NSEvent.mouseLocation
        var dragged = false
        while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if ev.type == .leftMouseDragged {
                let cur = NSEvent.mouseLocation
                if !dragged, hypot(cur.x - start.x, cur.y - start.y) > 5 {
                    dragged = true
                    beginNoteDrag(event: ev)
                    return
                }
            } else {
                if !dragged { onEvent(.select(noteId)) }
                return
            }
        }
    }

    private func beginNoteDrag(event: NSEvent) {
        let writer = NoteDragWriter(noteId)
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.draggingFrame = NSRect(origin: event.locationInWindow, size: NSSize(width: 160, height: 28))
        // Without explicit image components, AppKit snapshots the source row.
        beginDraggingSession(with: [item], event: event, source: self)
    }
}

extension NoteRowView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }
}

/// Pasteboard writer carrying a single note id (custom type).
final class NoteDragWriter: NSObject, NSPasteboardWriting {
    let noteId: String
    init(_ id: String) { self.noteId = id }
    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        return [SidebarViewController.noteIdPBType]
    }
    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        return noteId
    }
}

// MARK: - Small UI helpers

/// A tiny borderless icon/text button used in headers & rows.
final class SmallIconButton: NSButton {
    var onActivate: (() -> Void)?
    init(title: String, tooltip: String) {
        super.init(frame: .zero)
        self.title = title
        self.toolTip = tooltip
        isBordered = false
        font = NSFont.systemFont(ofSize: 12)
        contentTintColor = Theme.textDim
        focusRingType = .none
        target = self
        action = #selector(click)
        wantsLayer = true
        layer?.cornerRadius = 4
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func click() {
        onActivate?()
    }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = Theme.elevated.cgColor
        contentTintColor = Theme.text
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
        contentTintColor = Theme.textDim
    }
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }
}

/// Small filled/outlined pill button (cat-ok / cat-cancel / del-yes / del-no).
final class MiniButton: NSView {
    private let label: NSTextField
    init(title: String, filled: Bool = false, danger: Bool = false, onClick: @escaping () -> Void) {
        self.onClick = onClick
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        label.font = NSFont.systemFont(ofSize: 10)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
        if danger {
            layer?.backgroundColor = Theme.danger.cgColor
            label.textColor = .white
        } else if filled {
            layer?.backgroundColor = Theme.accent.cgColor
            label.textColor = .white
        } else {
            layer?.backgroundColor = Theme.elevated.cgColor
            label.textColor = Theme.textDim
        }
        let click = NSClickGestureRecognizer(target: self, action: #selector(tap))
        addGestureRecognizer(click)
    }
    required init?(coder: NSCoder) { fatalError() }
    private let onClick: () -> Void
    @objc private func tap() { onClick() }
}

/// Hover observer: owns a tracking area's events and forwards enter/exit.
/// The host view must retain it (NSTrackingArea does not retain its owner).
final class HoverObserver: NSObject {
    let onChange: (Bool) -> Void
    init(_ onChange: @escaping (Bool) -> Void) { self.onChange = onChange }
    func mouseEntered(with event: NSEvent) { onChange(true) }
    func mouseExited(with event: NSEvent) { onChange(false) }
}

/// Install (and replace) a hover tracking area on `view`, retaining its owner.
@discardableResult
func installHoverTracker(on view: NSView, onChange: @escaping (Bool) -> Void) -> HoverObserver {
    let obs = HoverObserver(onChange)
    let area = NSTrackingArea(rect: view.bounds,
                              options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                              owner: obs, userInfo: nil)
    view.addTrackingArea(area)
    objc_setAssociatedObject(view, &hoverObserverKey, obs, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return obs
}

private var hoverObserverKey: UInt8 = 0
