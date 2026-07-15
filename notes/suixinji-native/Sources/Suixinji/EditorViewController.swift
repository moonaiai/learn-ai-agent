import AppKit

protocol EditorViewControllerDelegate: AnyObject {
    func noteMetaDidChange(_ noteId: String)
    func noteWasDeleted(_ noteId: String)
    func editorRequestsHide()
    func editorSaveStatus(_ text: String)
}

/// Common lifecycle surface for the two editor implementations.
///
/// The existing NSTextView editor deliberately remains the default. The
/// WKWebView editor implements this same surface so the native AppKit panel,
/// sidebar, categories, and note lifecycle do not depend on the editor engine.
protocol NoteEditorController: AnyObject {
    var view: NSView { get }
    var delegate: EditorViewControllerDelegate? { get set }
    var currentNoteId: String? { get }
    var hasUnsavedChanges: Bool { get }

    func newNote()
    func openNote(id: String)
    func flush(userInitiated: Bool)
    func focus()
    func handlePaste() -> Bool
    /// Returns true when the editor consumed Escape (for example, an image
    /// preview overlay). Returning false lets the native panel hide itself.
    func handleEscape() -> Bool
}

let NoteIcons = ["📝", "💡", "✅", "🐛", "📚", "🔖", "🎯", "⚡"]

/// Right pane of the list view: a rich NSTextView with a formatting toolbar.
///
/// Mirrors `src/components/Editor.tsx`:
/// - no separate header / title field — the note title is derived from the
///   first non-empty line on save.
/// - the note icon lives in the toolbar (icon-picker button + dropdown menu).
/// - category is assigned via drag in the sidebar, never from the editor.
/// - save status is reported up to the top bar, not rendered here.
final class EditorViewController: NSViewController, NoteEditorController {

    weak var delegate: EditorViewControllerDelegate?

    private let store: NotesStore
    private(set) var currentNoteId: String?
    private var meta: NoteMeta?
    private var dirty = false
    private var persisted = false
    private var saveTimer: Timer?
    private var suppressChange = false

    private let textView = EditorTextView()
    private weak var editorScrollView: NSScrollView?
    private var fontPopup: ToolbarMenuButton!
    private var fontSizePopup: ToolbarMenuButton!
    private var headingPopup: ToolbarMenuButton!
    private var iconButton: NSButton!
    private var tableOpButtons: [NSButton] = []
    private var formattingButtons: [String: ToolbarButton] = [:]
    private var availableFontFamilies: [String] = []
    private let headingTitles = ["正文", "H1", "H2", "H3", "H4", "H5"]
    private let fontSizeTitles = ["12", "14", "15", "18", "24"]

    /// True when the current note has edits that have not reached disk yet.
    /// MainViewController uses this to distinguish an untouched scratch note
    /// from a scratch note that should be finalized before creating another.
    var hasUnsavedChanges: Bool { dirty }

    init(store: NotesStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View lifecycle

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.editorBackground.cgColor

        let toolbar = makeToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        // Install the clip view before the document view. AppKit transfers the
        // document view to a newly assigned clip view, but assigning it after
        // `documentView` can leave the text view detached on macOS 26.
        scroll.contentView = EditorClipView()
        scroll.documentView = textView
        // Scrolling remains available through the wheel/trackpad even when
        // the scroller is disabled. Keeping it out of the layout prevents
        // AppKit from changing the editor's content geometry on focus.
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        // AppKit may add automatic safe-area/scroller insets when the panel
        // becomes key. That changes the text origin only while editing, which
        // is the visible left-margin jump. The editor owns its inset below,
        // so the scroll view must not add another one.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets()
        scroll.scrollerInsets = NSEdgeInsets()
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        editorScrollView = scroll

        // The textView is created with a .zero frame (see EditorTextView.init).
        // Without an autoresizing mask or constraints tracking the clip view,
        // its frame — and therefore the textContainer width — stays 0 and the
        // editor renders blank. Pin it to the clip view's width so text wraps
        // and reflows with the window; height grows with content because
        // isVerticallyResizable is already true. Seed a non-zero container
        // width so text is laid out before the first clip-view resize arrives.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            let seedWidth = max(scroll.contentView.bounds.width, 480)
            container.size = NSSize(width: seedWidth, height: CGFloat.greatestFiniteMagnitude)
        }

        view.addSubview(toolbar)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        self.view = view
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateEditorDocumentSize()
    }

    /// Keep the NSTextView document taller than the clip view when content
    /// grows. The toolbar is a sibling above the scroll view, so it remains
    /// fixed while only the editor content scrolls.
    private func updateEditorDocumentSize() {
        guard let scroll = editorScrollView,
              let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

        let width = max(scroll.contentView.bounds.width, 1)
        // Formatting changes invalidate glyph metrics and can change the
        // document view's height. Preserve the current scroll position before
        // resizing it; otherwise NSClipView falls back to y=0 after every
        // heading/list/quote/code operation.
        let preservedScrollY = max(0, scroll.contentView.bounds.origin.y)
        // NSTextView must occupy the full clip width. Otherwise NSClipView
        // centers a shorter document view while it is inactive, then shifts
        // it back when the caret becomes active.
        var bounds = scroll.contentView.bounds
        if abs(bounds.origin.x) > 0.5 {
            bounds.origin.x = 0
            scroll.contentView.setBoundsOrigin(bounds.origin)
        }
        if abs(textView.frame.width - width) > 0.5 {
            textView.setFrameSize(NSSize(width: width, height: max(textView.frame.height, 1)))
        }
        // A document view belongs at the clip view's origin. Leaving a stale
        // vertical frame origin lets NSClipView center the short document when
        // inactive and move it back when editing starts, causing the top
        // margin to jump just like the horizontal margin.
        if abs(textView.frame.minX) > 0.5 || abs(textView.frame.minY) > 0.5 {
            textView.setFrameOrigin(NSPoint(x: 0, y: 0))
        }
        container.widthTracksTextView = true
        // Update the container immediately with the same width as the clip
        // view. Waiting for the next layout pass lets NSTextView temporarily
        // center a stale, narrower container when it becomes first responder.
        container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        // Fit after the text view/container has the real window width. This is
        // also required when a note is opened after the initial layout pass;
        // otherwise an old attachment can keep its original oversized bounds.
        textView.fitEmbeddedImagesToAvailableWidth()
        layoutManager.ensureLayout(for: container)

        let usedHeight = layoutManager.usedRect(for: container).height
            + textView.textContainerInset.height * 2
        let height = max(scroll.contentView.bounds.height, ceil(usedHeight))
        if abs(textView.frame.height - height) > 0.5 {
            textView.setFrameSize(NSSize(width: width, height: height))
        }

        let maxScrollY = max(0, textView.frame.height - scroll.contentView.bounds.height)
        var restoredBounds = scroll.contentView.bounds
        restoredBounds.origin.x = 0
        restoredBounds.origin.y = min(preservedScrollY, maxScrollY)
        if restoredBounds.origin != scroll.contentView.bounds.origin {
            scroll.contentView.setBoundsOrigin(restoredBounds.origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.editorDelegate = self
        textView.delegate = self
    }

    // MARK: - Toolbar (App.css .toolbar / .tb-btn)

    private func makeToolbar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        // Keep the formatting strip visually separate from the left list
        // surface; the 1pt split divider in MainViewController completes the
        // two-pane separation.
        bar.layer?.backgroundColor = Theme.elevated.cgColor

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        stack.alignment = .centerY
        stack.heightAnchor.constraint(equalToConstant: 40).isActive = true

        func iconBtn(_ symbolName: String, fallback: String, _ action: Selector, _ tooltip: String,
                     enabled: Bool = true, formatKey: String? = nil) -> ToolbarButton {
            let b = ToolbarButton(title: fallback, target: self, action: action)
            b.toolTip = tooltip
            b.isEnabled = enabled
            b.font = NSFont.systemFont(ofSize: 14, weight: .medium)
            b.contentTintColor = Theme.textDim
            if let image = NSImage(systemSymbolName: symbolName,
                                   accessibilityDescription: tooltip) {
                image.isTemplate = true
                b.image = image
                b.imagePosition = .imageOnly
                b.imageScaling = .scaleProportionallyDown
            } else {
                // Keep the semantic fallback visible on older macOS symbol
                // sets instead of leaving an image-only button blank.
                b.imagePosition = .noImage
            }
            b.setAccessibilityLabel(tooltip)
            b.widthAnchor.constraint(equalToConstant: 24).isActive = true
            b.heightAnchor.constraint(equalToConstant: 28).isActive = true
            if !enabled {
                tableOpButtons.append(b)
                b.isHidden = true
            }
            if let formatKey {
                formattingButtons[formatKey] = b
            }
            return b
        }

        fontPopup = ToolbarMenuButton(title: "系统字体", target: self,
                                      action: #selector(showFontMenu(_:)))
        fontPopup.toolTip = "字体"
        let availableFamilies = Set(NSFontManager.shared.availableFontFamilies)
        availableFontFamilies = ["系统字体"] + [
            "Helvetica Neue", "PingFang SC", "Hiragino Sans GB", "Songti SC",
            "Heiti SC", "Noto Sans CJK SC", "Menlo", "Monaco", "Arial", "Georgia"
        ].filter { availableFamilies.contains($0) }
        // Keep the font control the same compact size as the other toolbar
        // controls. Long family names are truncated inside this fixed width.
        fontPopup.widthAnchor.constraint(equalToConstant: 72).isActive = true
        fontPopup.heightAnchor.constraint(equalToConstant: 28).isActive = true

        fontSizePopup = ToolbarMenuButton(title: "15", target: self,
                                          action: #selector(showFontSizeMenu(_:)))
        fontSizePopup.toolTip = "字号"
        fontSizePopup.widthAnchor.constraint(equalToConstant: 42).isActive = true
        fontSizePopup.heightAnchor.constraint(equalToConstant: 28).isActive = true

        headingPopup = ToolbarMenuButton(title: "正文", target: self,
                                         action: #selector(showHeadingMenu(_:)))
        headingPopup.toolTip = "段落样式"
        headingPopup.widthAnchor.constraint(equalToConstant: 48).isActive = true
        headingPopup.heightAnchor.constraint(equalToConstant: 28).isActive = true

        stack.addArrangedSubview(iconBtn("bold", fallback: "B", #selector(toggleBold(_:)), "加粗 ⌘B",
                                        formatKey: "bold"))
        stack.addArrangedSubview(iconBtn("italic", fallback: "I", #selector(toggleItalic(_:)), "斜体 ⌘I",
                                        formatKey: "italic"))
        stack.addArrangedSubview(iconBtn("strikethrough", fallback: "S", #selector(toggleStrike(_:)), "删除线",
                                        formatKey: "strike"))
        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(fontPopup)
        stack.addArrangedSubview(fontSizePopup)
        stack.addArrangedSubview(headingPopup)
        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(iconBtn("list.bullet", fallback: "•", #selector(toggleBulletList(_:)), "无序列表",
                                        formatKey: "bullet"))
        stack.addArrangedSubview(iconBtn("list.number", fallback: "1.", #selector(toggleNumberList(_:)), "有序列表",
                                        formatKey: "number"))
        stack.addArrangedSubview(iconBtn("text.quote", fallback: "❝", #selector(applyQuote(_:)), "引用",
                                        formatKey: "quote"))
        stack.addArrangedSubview(iconBtn("chevron.left.forwardslash.chevron.right", fallback: "<>",
                                        #selector(applyCode(_:)), "代码片段", formatKey: "code"))
        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(iconBtn("tablecells", fallback: "▦", #selector(insertTable(_:)), "插入表格"))
        // Table actions stay compact and appear only while the caret is inside
        // a table, so the normal editor toolbar remains uncluttered.
        stack.addArrangedSubview(iconBtn("table.row.insert.below", fallback: "+▭",
                                        #selector(addRowAfter(_:)), "添加一行", enabled: false))
        stack.addArrangedSubview(iconBtn("table.row.delete", fallback: "−▭",
                                        #selector(deleteRow(_:)), "删除当前行", enabled: false))
        stack.addArrangedSubview(iconBtn("table.column.insert.after", fallback: "+▯",
                                        #selector(addColumnAfter(_:)), "添加一列", enabled: false))
        stack.addArrangedSubview(iconBtn("table.column.delete", fallback: "−▯",
                                        #selector(deleteColumn(_:)), "删除当前列", enabled: false))
        stack.addArrangedSubview(iconBtn("trash", fallback: "⌫",
                                        #selector(deleteTable(_:)), "删除表格", enabled: false))
        stack.addArrangedSubview(divider())

        // Icon picker button (shows the current note icon; click → dropdown menu).
        iconButton = ToolbarButton(title: "📝", target: self, action: #selector(showIconMenu(_:)))
        iconButton.toolTip = "笔记图标"
        iconButton.font = NSFont.systemFont(ofSize: 14)
        iconButton.contentTintColor = Theme.text
        iconButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        iconButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stack.addArrangedSubview(iconButton)

        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
        return bar
    }

    private func divider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = Theme.border.cgColor
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return v
    }

    // MARK: - Public API

    /// Open an existing note by id.
    func openNote(id: String) {
        if currentNoteId != id { flush() }
        currentNoteId = id
        suppressChange = true
        defer { suppressChange = false }

        let attr = store.loadAttributedString(id) ?? NSAttributedString(string: "")
        let m = store.listNotes().first { $0.id == id }
            ?? NoteMeta(id: id, title: store.deriveTitle(from: attr), icon: "📝", category: "",
                        mtime: Int(Date().timeIntervalSince1970))
        meta = m
        persisted = true

        textView.textStorage?.setAttributedString(attr)
        normalizeLoadedParagraphStyles()
        textView.selectedRange = NSRange(location: 0, length: 0)
        let para = (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        para.lineHeightMultiple = Theme.editorLineHeightMultiple
        textView.typingAttributes = [.font: Theme.bodyFont,
                                     .foregroundColor: Theme.text,
                                     .paragraphStyle: para]
        syncTypingAttributesWithCurrentParagraph()
        updateFormattingControls()

        iconButton.title = m.icon
        dirty = false
        saveTimer?.invalidate()
        delegate?.editorSaveStatus("")
        resetEditorViewportToTop()
    }

    /// Create and open a fresh blank note (does not persist until edited).
    func newNote() {
        let id = newNoteId()
        let m = NoteMeta(id: id, title: "", icon: "📝", category: "",
                         mtime: Int(Date().timeIntervalSince1970))
        currentNoteId = id
        meta = m
        persisted = false
        suppressChange = true
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        let para = (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        para.lineHeightMultiple = Theme.editorLineHeightMultiple
        textView.typingAttributes = [.font: Theme.bodyFont,
                                     .foregroundColor: Theme.text,
                                     .paragraphStyle: para]
        iconButton.title = m.icon
        updateFormattingControls()
        suppressChange = false
        dirty = false
        saveTimer?.invalidate()
        delegate?.editorSaveStatus("")
        resetEditorViewportToTop()
    }

    /// Reset the document geometry when switching notes. NSClipView can keep
    /// the previous document's vertical origin while NSTextView is relaid out;
    /// when the new note becomes first responder that stale origin is exposed
    /// as a growing top margin. Re-layout first, then explicitly restore the
    /// document and clip view to their canonical origin.
    private func resetEditorViewportToTop() {
        guard let scroll = editorScrollView,
              let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

        view.layoutSubtreeIfNeeded()
        updateEditorDocumentSize()

        let contentLength = textView.textStorage?.length ?? 0
        layoutManager.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: contentLength),
            actualCharacterRange: nil)
        layoutManager.ensureLayout(for: container)

        textView.setFrameOrigin(.zero)
        var bounds = scroll.contentView.bounds
        bounds.origin = .zero
        scroll.contentView.setBoundsOrigin(bounds.origin)
        scroll.reflectScrolledClipView(scroll.contentView)
        textView.needsDisplay = true
    }

    /// Persist immediately if there is a dirty note.
    func flush(userInitiated: Bool = false) {
        guard let id = currentNoteId, let m = meta,
              dirty || (userInitiated && !persisted) else { return }
        var updated = m
        // The title is the first non-empty line. There is no separate title field.
        updated.title = store.deriveTitle(from: textView.attributedString())
        store.saveNote(id: id, content: textView.attributedString(), meta: updated)
        meta = updated
        persisted = true
        dirty = false
        saveTimer?.invalidate()
        let now = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        delegate?.editorSaveStatus(userInitiated ? "已保存 \(now)" : "已自动保存 \(now)")
        delegate?.noteMetaDidChange(id)
    }

    /// Make the editor text view the key focus.
    func focus() {
        view.window?.makeFirstResponder(textView)
    }

    func handleEscape() -> Bool { false }
    func handlePaste() -> Bool { false }

    // MARK: - Toolbar formatting actions

    @objc private func showFontMenu(_ sender: ToolbarMenuButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = NSAppearance(named: .darkAqua)
        for family in availableFontFamilies {
            let item = NSMenuItem(title: family, action: #selector(applyFontFamily(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = family
            item.state = sender.menuTitle == family ? .on : .off
            item.attributedTitle = NSAttributedString(string: family, attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: Theme.text,
            ])
            menu.addItem(item)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.height + 2),
                   in: sender)
    }

    @objc private func showHeadingMenu(_ sender: ToolbarMenuButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = NSAppearance(named: .darkAqua)
        for (index, title) in headingTitles.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(applyHeadingSelection(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = sender.menuTitle == title ? .on : .off
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: index == 0 ? .regular : .semibold),
                .foregroundColor: Theme.text,
            ])
            menu.addItem(item)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.height + 2),
                   in: sender)
    }

    @objc private func showFontSizeMenu(_ sender: ToolbarMenuButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = NSAppearance(named: .darkAqua)
        for title in fontSizeTitles {
            let item = NSMenuItem(title: title, action: #selector(applyFontSize(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = title
            item.state = sender.menuTitle == title ? .on : .off
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: Theme.text,
            ])
            menu.addItem(item)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.height + 2),
                   in: sender)
    }

    @objc private func applyFontFamily(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        let family = (item.representedObject as? String) ?? item.title
        let range = textView.selectedRange()

        if range.length == 0 {
            var attrs = textView.typingAttributes
            let current = (attrs[.font] as? NSFont) ?? Theme.bodyFont
            attrs[.font] = fontByChangingFamily(current, family: family)
            textView.typingAttributes = attrs
            updateFormattingControls()
            return
        }

        guard let storage = textView.textStorage else { return }
        let before = attributedSnapshot()
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let current = (value as? NSFont) ?? Theme.bodyFont
            storage.addAttribute(.font,
                                 value: self.fontByChangingFamily(current, family: family),
                                 range: subrange)
        }
        storage.endEditing()
        registerFormattingUndo(before: before, selectionBefore: range, actionName: "字体")
        textView.needsDisplay = true
        updateFormattingControls()
        markDirty()
    }

    @objc private func applyFontSize(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        let raw = ((item.representedObject as? String) ?? item.title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(raw), value >= 6, value <= 96 else {
            updateFormattingControls()
            return
        }
        let size = CGFloat(value)
        let range = textView.selectedRange()

        if range.length == 0 {
            var attrs = textView.typingAttributes
            let current = (attrs[.font] as? NSFont) ?? Theme.bodyFont
            attrs[.font] = fontByChangingSize(current, size: size)
            textView.typingAttributes = attrs
            updateFormattingControls()
            return
        }

        guard let storage = textView.textStorage else { return }
        let before = attributedSnapshot()
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let current = (value as? NSFont) ?? Theme.bodyFont
            storage.addAttribute(.font,
                                 value: self.fontByChangingSize(current, size: size),
                                 range: subrange)
        }
        storage.endEditing()
        registerFormattingUndo(before: before, selectionBefore: range, actionName: "字号")
        textView.needsDisplay = true
        updateFormattingControls()
        markDirty()
    }

    private func fontByChangingFamily(_ font: NSFont, family: String) -> NSFont {
        let base: NSFont
        if family == "系统字体" {
            base = NSFont.systemFont(ofSize: font.pointSize)
        } else {
            base = NSFont(name: family, size: font.pointSize) ?? font
        }
        var result = base
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.bold) {
            result = NSFontManager.shared.convert(result, toHaveTrait: .boldFontMask)
        }
        if traits.contains(.italic) {
            result = NSFontManager.shared.convert(result, toHaveTrait: .italicFontMask)
        }
        return result
    }

    private func fontByChangingSize(_ font: NSFont, size: CGFloat) -> NSFont {
        NSFont(descriptor: font.fontDescriptor.withSize(size), size: size)
            ?? NSFont.systemFont(ofSize: size)
    }

    /// Heading changes must preserve the active font family. Starting from
    /// Theme.bodyFont here would turn an Arial/PingFang paragraph back into
    /// the system font as soon as H1-H5 is selected.
    private func headingFont(from base: NSFont, size: CGFloat) -> NSFont {
        var result = fontByChangingSize(base, size: size)
        if !result.fontDescriptor.symbolicTraits.contains(.bold) {
            result = NSFontManager.shared.convert(result, toHaveTrait: .boldFontMask)
        }
        return result
    }

    private func bodyFont(from base: NSFont) -> NSFont {
        var result = fontByChangingSize(base, size: Theme.bodyFont.pointSize)
        if result.fontDescriptor.symbolicTraits.contains(.bold) {
            result = NSFontManager.shared.convert(result, toHaveTrait: .unboldFontMask)
        }
        return result
    }

    /// Read the attributes at the caret itself. `typingAttributes` can lag
    /// behind after a paragraph format is changed directly in NSTextStorage.
    private func formattingAttributes() -> [NSAttributedString.Key: Any] {
        guard let storage = textView.textStorage, storage.length > 0 else {
            return textView.typingAttributes
        }
        let selection = textView.selectedRange()
        if selection.length == 0 {
            // At an empty selection, toolbar changes intentionally live in
            // typingAttributes until the next character is inserted. Reading
            // the old storage run here would make font changes appear to do
            // nothing. Paragraph-format operations explicitly synchronize
            // typingAttributes after changing storage.
            return textView.typingAttributes
        }
        let location = min(selection.location, storage.length - 1)
        return storage.attributes(at: location, effectiveRange: nil)
    }

    private func isHeadingAttributes(_ attributes: [NSAttributedString.Key: Any],
                                     size: CGFloat) -> Bool {
        guard let font = attributes[.font] as? NSFont,
              abs(font.pointSize - size) < 0.5 else { return false }
        let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
        let hasHeadingSpacing = (paragraph?.paragraphSpacingBefore ?? 0) >= 7.5
            && (paragraph?.paragraphSpacing ?? 0) >= 3.5
        return font.fontDescriptor.symbolicTraits.contains(.bold) || hasHeadingSpacing
    }

    private func updateFormattingControls() {
        guard fontPopup != nil, fontSizePopup != nil, headingPopup != nil else { return }
        let attributes = formattingAttributes()
        let font = attributes[.font] as? NSFont
        guard let font else { return }
        let family = font.familyName ?? font.fontName
        if availableFontFamilies.contains(family) {
            if fontPopup.menuTitle != family {
                fontPopup.setMenuTitle(family)
            }
        } else if family == ".AppleSystemUIFont" || family == "系统字体" {
            if fontPopup.menuTitle != "系统字体" {
                fontPopup.setMenuTitle("系统字体")
            }
        }
        let sizeTitle = String(format: "%.1f", font.pointSize)
            .replacingOccurrences(of: ".0", with: "")
        if fontSizePopup.menuTitle != sizeTitle {
            fontSizePopup.setMenuTitle(sizeTitle)
        }

        let headingIndex: Int
        switch Int(font.pointSize.rounded()) {
        case 24: headingIndex = isHeadingAttributes(attributes, size: 24) ? 1 : 0
        case 20: headingIndex = isHeadingAttributes(attributes, size: 20) ? 2 : 0
        case 18: headingIndex = isHeadingAttributes(attributes, size: 18) ? 3 : 0
        case 16: headingIndex = isHeadingAttributes(attributes, size: 16) ? 4 : 0
        case 14: headingIndex = isHeadingAttributes(attributes, size: 14) ? 5 : 0
        default: headingIndex = 0
        }
        let headingTitle = headingTitles[headingIndex]
        if headingPopup.menuTitle != headingTitle {
            headingPopup.setMenuTitle(headingTitle)
        }

        let traits = font.fontDescriptor.symbolicTraits
        formattingButtons["bold"]?.setActive(traits.contains(.bold))
        formattingButtons["italic"]?.setActive(traits.contains(.italic))
        let strikeValue = (attributes[.strikethroughStyle] as? NSNumber)?.intValue
            ?? (attributes[.strikethroughStyle] as? Int ?? 0)
        formattingButtons["strike"]?.setActive(strikeValue != 0)

        var bulletActive = false
        var numberActive = false
        var quoteActive = false
        var codeActive = false
        if let storage = textView.textStorage, storage.length > 0 {
            let location = min(textView.selectedRange().location, storage.length - 1)
            let paragraphRange = (storage.string as NSString).lineRange(
                for: NSRange(location: location, length: 0))
            if let prefix = simpleListPrefix(in: paragraphRange, string: storage.string as NSString) {
                bulletActive = !prefix.numbered
                numberActive = prefix.numbered
            }
            if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle {
                quoteActive = paragraph.headIndent >= 20
                    && paragraph.firstLineHeadIndent >= 20
            }
            codeActive = paragraphIsCode(paragraphRange, storage: storage)
        }
        formattingButtons["bullet"]?.setActive(bulletActive)
        formattingButtons["number"]?.setActive(numberActive)
        formattingButtons["quote"]?.setActive(quoteActive)
        formattingButtons["code"]?.setActive(codeActive)

        // Font, size, and heading are value menus: their current value is
        // already shown in the control, so they should not receive the same
        // toggle-style active background as boolean formatting buttons.
    }

    @objc func toggleBold(_ sender: Any?) {
        applyFontTrait(mask: .boldFontMask, opposite: .unboldFontMask, symbolic: .bold)
    }
    @objc func toggleItalic(_ sender: Any?) {
        applyFontTrait(mask: .italicFontMask, opposite: .unitalicFontMask, symbolic: .italic)
    }
    @objc func toggleStrike(_ sender: Any?) { applyStrike() }

    @objc func applyH1(_ sender: Any?) { toggleHeading(size: 24) }
    @objc func applyH2(_ sender: Any?) { toggleHeading(size: 20) }
    @objc func applyH3(_ sender: Any?) { toggleHeading(size: 18) }
    @objc func applyH4(_ sender: Any?) { toggleHeading(size: 16) }
    @objc func applyH5(_ sender: Any?) { toggleHeading(size: 14) }

    @objc private func applyHeadingSelection(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        switch item.tag {
        case 1: toggleHeading(size: 24)
        case 2: toggleHeading(size: 20)
        case 3: toggleHeading(size: 18)
        case 4: toggleHeading(size: 16)
        case 5: toggleHeading(size: 14)
        default: toggleHeading(size: 15, forceRemove: true)
        }
    }

    @objc func toggleBulletList(_ sender: Any?) { toggleList(numbered: false) }
    @objc func toggleNumberList(_ sender: Any?) { toggleList(numbered: true) }

    @objc func applyQuote(_ sender: Any?) {
        let before = attributedSnapshot()
        let selection = textView.selectedRange()
        let string = textView.string as NSString
        let lineRange = string.lineRange(for: selection)
        var quoted = true
        if let storage = textView.textStorage {
            storage.enumerateAttribute(.paragraphStyle, in: lineRange, options: []) { value, _, _ in
                guard let paragraph = value as? NSParagraphStyle,
                      paragraph.headIndent >= 20,
                      paragraph.firstLineHeadIndent >= 20 else {
                    quoted = false
                    return
                }
            }
        }
        applyToParagraphs { existing in
            let p = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            if quoted {
                p.headIndent = 0
                p.firstLineHeadIndent = 0
                return (p, [.foregroundColor: Theme.text])
            } else {
                p.headIndent = 22
                p.firstLineHeadIndent = 22
                return (p, [.foregroundColor: Theme.quoteColor])
            }
        }
        registerFormattingUndo(before: before, selectionBefore: selection, actionName: "引用")
        syncTypingAttributesWithCurrentParagraph()
        updateFormattingControls()
        markDirty()
    }

    @objc func applyCode(_ sender: Any?) {
        let range = textView.selectedRange()
        guard range.length > 0 else {
            var attrs = textView.typingAttributes
            let font = attrs[.font] as? NSFont
            let isCode = font?.fontName.lowercased().contains("mono") == true
                || (attrs[.backgroundColor] as? NSColor)?.isEqual(Theme.codeBackground) == true
            if isCode {
                attrs[.font] = Theme.bodyFont
                attrs[.foregroundColor] = Theme.text
                attrs.removeValue(forKey: .backgroundColor)
            } else {
                attrs[.font] = Theme.monoFont
                attrs[.foregroundColor] = Theme.text
                attrs[.backgroundColor] = Theme.codeBackground
            }
            textView.typingAttributes = attrs
            updateFormattingControls()
            return
        }
        guard let storage = textView.textStorage else { return }
        let before = attributedSnapshot()
        let selectionBefore = range
        let string = storage.string as NSString
        let lineRange = string.lineRange(for: range)
        var paragraphs: [NSRange] = []
        enumerateParagraphRanges(in: lineRange) { paragraphs.append($0) }
        let isCode = !paragraphs.isEmpty && paragraphs.allSatisfy { paragraphIsCode($0, storage: storage) }

        storage.beginEditing()
        for paragraphRange in paragraphs {
            let paragraph = (storage.attribute(.paragraphStyle, at: paragraphRange.location,
                                                effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy()
                as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.textBlocks = []
            paragraph.lineHeightMultiple = Theme.editorLineHeightMultiple
            paragraph.paragraphSpacingBefore = isCode ? 0 : 4
            paragraph.paragraphSpacing = isCode ? 0 : 4
            storage.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
            if isCode {
                storage.addAttribute(.font, value: Theme.bodyFont, range: paragraphRange)
                storage.addAttribute(.foregroundColor, value: Theme.text, range: paragraphRange)
                storage.removeAttribute(.backgroundColor, range: paragraphRange)
            } else {
                storage.addAttribute(.font, value: Theme.monoFont, range: paragraphRange)
                storage.addAttribute(.foregroundColor, value: Theme.text, range: paragraphRange)
                storage.addAttribute(.backgroundColor, value: Theme.codeBackground, range: paragraphRange)
            }
        }
        storage.endEditing()
        if !isCode {
            for paragraphRange in paragraphs { highlightCode(in: paragraphRange, storage: storage) }
        }
        registerFormattingUndo(before: before, selectionBefore: selectionBefore,
                               actionName: isCode ? "取消代码" : "代码")
        updateFormattingControls()
        markDirty()
    }

    private func paragraphIsCode(_ range: NSRange, storage: NSTextStorage) -> Bool {
        guard storage.length > 0 else { return false }
        let location = min(range.location, storage.length - 1)
        let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        let background = storage.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor
        return font?.fontName.lowercased().contains("mono") == true
            || background?.isEqual(Theme.codeBackground) == true
    }

    /// Lightweight language-agnostic highlighting for common Swift,
    /// JavaScript, Python and shell snippets. It intentionally avoids a
    /// language picker: the editor only needs readable code, not a compiler.
    private func highlightCode(in range: NSRange, storage: NSTextStorage) {
        guard range.length > 0 else { return }
        storage.addAttribute(.font, value: Theme.monoFont, range: range)
        storage.addAttribute(.foregroundColor, value: Theme.text, range: range)
        storage.addAttribute(.backgroundColor, value: Theme.codeBackground, range: range)
        let source = storage.string as NSString
        let code = source.substring(with: range)
        let patterns: [(String, NSColor)] = [
            (#"//[^\n]*|#[^\n]*"#, Theme.codeComment),
            (#"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#, Theme.codeString),
            (#"\b(if|else|for|while|in|func|function|def|class|struct|enum|let|var|const|return|import|from|async|await|try|catch|throw|true|false|nil|null|None)\b"#, Theme.codeKeyword),
            (#"\b\d+(?:\.\d+)?\b"#, Theme.codeNumber),
        ]
        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: code, options: [], range: NSRange(location: 0, length: (code as NSString).length))
            for match in matches {
                let absolute = NSRange(location: range.location + match.range.location,
                                        length: match.range.length)
                storage.addAttribute(.foregroundColor, value: color, range: absolute)
            }
        }
    }

    @objc func insertImageMenu(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            // Prefer the raw-bytes fidelity path: insertImageFromURL keeps the
            // original file bytes verbatim (no NSImage re-encode). Only fall
            // back to the NSImage path if reading the URL fails.
            if self.textView.insertImageFromURL(url) {
                self.markDirty()
                return
            }
            if let img = NSImage(contentsOf: url) {
                self.textView.insertImage(img, suggestedName: url.lastPathComponent)
                self.markDirty()
            }
        }
    }

    @objc private func showIconMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for ic in NoteIcons {
            let item = NSMenuItem(title: ic, action: #selector(pickIcon(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ic
            item.state = (meta?.icon == ic) ? .on : .off
            menu.addItem(item)
        }
        let origin = NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 2)
        menu.popUp(positioning: nil, at: origin, in: sender)
    }

    @objc private func pickIcon(_ sender: NSMenuItem) {
        guard var m = meta else { return }
        m.icon = sender.title
        meta = m
        iconButton.title = m.icon
        markDirty()
    }

    // MARK: - Table actions

    @objc func insertTable(_ sender: Any?) {
        let range = textView.selectedRange()
        let rows = Array(repeating: Array(repeating: NSAttributedString(string: ""), count: 3), count: 3)
        replaceSelectionWithTable(rows: rows, selection: range)
        markDirty()
    }

    @objc func deleteTable(_ sender: Any?) {
        guard let table = currentTable() else { return }
        guard let storage = textView.textStorage,
              let range = tableRange(for: table) else { return }
        storage.deleteCharacters(in: range)
        textView.setSelectedRange(NSRange(location: min(range.location, storage.length), length: 0))
        markDirty()
    }

    @objc func addRowBefore(_ sender: Any?) { mutateRow(before: true) }
    @objc func addRowAfter(_ sender: Any?) { mutateRow(before: false) }
    @objc func deleteRow(_ sender: Any?) { removeRow() }
    @objc func addColumnBefore(_ sender: Any?) { mutateColumn(before: true) }
    @objc func addColumnAfter(_ sender: Any?) { mutateColumn(before: false) }
    @objc func deleteColumn(_ sender: Any?) { removeColumn() }

    // MARK: - Formatting helpers

    private func attributedSnapshot() -> NSAttributedString {
        NSAttributedString(attributedString: textView.attributedString())
    }

    /// NSTextView automatically records character edits, but direct attribute
    /// and list-prefix mutations do not enter its undo stack. Store the whole
    /// rich-text snapshot for those formatting commands and register the
    /// inverse again while undoing, which gives Cmd+Z/Cmd+Shift+Z symmetric
    /// behavior for both text and formatting.
    private func registerFormattingUndo(before: NSAttributedString,
                                        selectionBefore: NSRange,
                                        actionName: String = "格式") {
        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.restoreAttributedSnapshot(before, selection: selectionBefore)
        }
        textView.undoManager?.setActionName(actionName)
    }

    private func restoreAttributedSnapshot(_ snapshot: NSAttributedString, selection: NSRange) {
        guard let storage = textView.textStorage else { return }
        let current = attributedSnapshot()
        let currentSelection = textView.selectedRange()
        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.restoreAttributedSnapshot(current, selection: currentSelection)
        }
        storage.setAttributedString(snapshot)
        let location = min(selection.location, storage.length)
        let length = min(selection.length, max(0, storage.length - location))
        textView.setSelectedRange(NSRange(location: location, length: length))
        syncTypingAttributesWithCurrentParagraph()
        textView.didChangeText()
        updateEditorDocumentSize()
        updateFormattingControls()
    }

    private func applyFontTrait(mask: NSFontTraitMask, opposite: NSFontTraitMask, symbolic: NSFontDescriptor.SymbolicTraits) {
        let range = textView.selectedRange()
        guard let storage = textView.textStorage else { return }

        if range.length == 0 {
            let font = (textView.typingAttributes[.font] as? NSFont) ?? Theme.bodyFont
            let has = font.fontDescriptor.symbolicTraits.contains(symbolic)
            let newFont = NSFontManager.shared.convert(font, toHaveTrait: has ? opposite : mask)
            var attrs = textView.typingAttributes
            attrs[.font] = newFont
            textView.typingAttributes = attrs
            updateFormattingControls()
            return
        }

        let before = attributedSnapshot()
        let selectionBefore = range
        storage.beginEditing()
        var shouldAdd = true
        storage.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
            let font = (value as? NSFont) ?? Theme.bodyFont
            if font.fontDescriptor.symbolicTraits.contains(symbolic) {
                shouldAdd = false
            }
        }
        storage.enumerateAttribute(.font, in: range, options: []) { value, r, _ in
            let font = (value as? NSFont) ?? Theme.bodyFont
            let newFont = NSFontManager.shared.convert(font, toHaveTrait: shouldAdd ? mask : opposite)
            storage.addAttribute(.font, value: newFont, range: r)
        }
        storage.endEditing()
        registerFormattingUndo(before: before, selectionBefore: selectionBefore,
                               actionName: symbolic == .bold ? "加粗" : "斜体")
        updateFormattingControls()
        markDirty()
    }

    private func applyStrike() {
        let range = textView.selectedRange()
        guard let storage = textView.textStorage else { return }
        let key = NSAttributedString.Key.strikethroughStyle

        if range.length == 0 {
            let has = (textView.typingAttributes[key] as? Int ?? 0) != 0
            var attrs = textView.typingAttributes
            attrs[key] = has ? 0 : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = attrs
            updateFormattingControls()
            return
        }

        let before = attributedSnapshot()
        let selectionBefore = range
        var shouldAdd = true
        storage.enumerateAttribute(key, in: range, options: []) { value, _, _ in
            if (value as? Int ?? 0) != 0 { shouldAdd = false }
        }
        storage.beginEditing()
        storage.addAttribute(key, value: shouldAdd ? NSUnderlineStyle.single.rawValue : 0, range: range)
        storage.endEditing()
        registerFormattingUndo(before: before, selectionBefore: selectionBefore, actionName: "删除线")
        updateFormattingControls()
        markDirty()
    }

    private func toggleHeading(size: CGFloat, forceRemove: Bool = false) {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        let string = storage.string as NSString
        let lineRange = string.lineRange(for: selection)
        var paragraphs: [NSRange] = []
        enumerateParagraphRanges(in: lineRange) { paragraphs.append($0) }

        let shouldRemove = forceRemove || (!paragraphs.isEmpty && paragraphs.allSatisfy {
            let location = min($0.location, max(storage.length - 1, 0))
            let attributes = storage.attributes(at: location, effectiveRange: nil)
            return self.isHeadingAttributes(attributes, size: size)
        })

        if paragraphs.isEmpty {
            var attrs = textView.typingAttributes
            let current = (attrs[.font] as? NSFont) ?? Theme.bodyFont
            attrs[.font] = shouldRemove
                ? bodyFont(from: current)
                : headingFont(from: current, size: size)
            attrs[.paragraphStyle] = headingParagraphStyle(removing: shouldRemove,
                                                            size: size,
                                                            from: attrs[.paragraphStyle] as? NSParagraphStyle)
            textView.typingAttributes = attrs
            return
        }

        let before = attributedSnapshot()
        let selectionBefore = selection
        storage.beginEditing()
        for paragraphRange in paragraphs {
            let existing = storage.attribute(.paragraphStyle, at: paragraphRange.location,
                                              effectiveRange: nil) as? NSParagraphStyle
            let fontLocation = min(paragraphRange.location, storage.length - 1)
            let currentFont = (storage.attribute(.font,
                                                  at: fontLocation,
                                                  effectiveRange: nil) as? NSFont) ?? Theme.bodyFont
            let paragraph = headingParagraphStyle(removing: shouldRemove,
                                                  size: size,
                                                  from: existing)
            let font = shouldRemove
                ? bodyFont(from: currentFont)
                : headingFont(from: currentFont, size: size)
            storage.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
            storage.addAttribute(.font, value: font, range: paragraphRange)
        }
        storage.endEditing()
        // Formatting changes invalidate glyph metrics. Ensure the new heading
        // line boxes are laid out before the next paragraph is drawn; otherwise
        // AppKit can briefly keep the old body line height and overlap text.
        if let container = textView.textContainer,
           let layoutManager = textView.layoutManager {
            layoutManager.ensureLayout(for: container)
        }
        textView.needsDisplay = true
        // Direct NSTextStorage edits do not refresh typingAttributes, so keep
        // the caret state synchronized before the toolbar reads it.
        syncTypingAttributesWithCurrentParagraph()
        updateEditorDocumentSize()
        registerFormattingUndo(before: before, selectionBefore: selectionBefore,
                               actionName: shouldRemove ? "取消标题" : "标题")
        updateFormattingControls()
        markDirty()
    }

    private func headingParagraphStyle(removing: Bool, size: CGFloat,
                                       from existing: NSParagraphStyle?) -> NSMutableParagraphStyle {
        let paragraph = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        paragraph.textLists = []
        paragraph.headIndent = 0
        paragraph.firstLineHeadIndent = 0
        paragraph.lineHeightMultiple = Theme.editorLineHeightMultiple
        paragraph.minimumLineHeight = removing ? 0 : ceil(size * Theme.editorLineHeightMultiple)
        paragraph.maximumLineHeight = 0
        paragraph.paragraphSpacingBefore = removing ? 0 : 8
        paragraph.paragraphSpacing = removing ? 0 : 4
        return paragraph
    }

    private struct SimpleListPrefix {
        let range: NSRange
        let numbered: Bool
    }

    /// AppKit's NSTextList is visually inconsistent when paragraphs are edited
    /// inside a borderless NSTextView. For this deliberately small editor,
    /// plain text prefixes are more predictable and still provide the intended
    /// bullet/numbered-list behavior.
    private func toggleList(numbered: Bool) {
        guard let storage = textView.textStorage else { return }
        let before = attributedSnapshot()
        let selectionBefore = textView.selectedRange()
        let string = storage.string as NSString
        let lineRange = string.lineRange(for: textView.selectedRange())
        var paragraphs: [NSRange] = []
        enumerateParagraphRanges(in: lineRange) { paragraphs.append($0) }
        guard !paragraphs.isEmpty else { return }

        let prefixes = paragraphs.map { simpleListPrefix(in: $0, string: string) }
        let alreadyApplied = prefixes.allSatisfy { $0?.numbered == numbered }

        storage.beginEditing()
        for (index, paragraphRange) in paragraphs.enumerated().reversed() {
            let prefix = prefixes[index]
            let oldPrefixLength = prefix?.range.length ?? 0
            if alreadyApplied {
                if let prefix { storage.deleteCharacters(in: prefix.range) }
            } else {
                if let prefix { storage.deleteCharacters(in: prefix.range) }
                let marker = numbered ? "\(index + 1). " : "• "
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: Theme.bodyFont,
                    .foregroundColor: Theme.text,
                ]
                storage.insert(NSAttributedString(string: marker, attributes: attrs),
                               at: paragraphRange.location)
            }

            let paragraph = (storage.attribute(.paragraphStyle, at: min(paragraphRange.location,
                                                                         max(storage.length - 1, 0)),
                                                effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy()
                as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.textLists = []
            paragraph.headIndent = 0
            paragraph.firstLineHeadIndent = 0
            let markerLength = numbered ? ("\(index + 1). ".utf16.count) : 2
            let delta = alreadyApplied ? -oldPrefixLength : markerLength - oldPrefixLength
            let newLength = max(0, paragraphRange.length + delta)
            if newLength > 0 {
                storage.addAttribute(.paragraphStyle, value: paragraph,
                                     range: NSRange(location: paragraphRange.location,
                                                     length: min(newLength, storage.length - paragraphRange.location)))
            }
        }
        storage.endEditing()
        textView.didChangeText()
        registerFormattingUndo(before: before, selectionBefore: selectionBefore,
                               actionName: alreadyApplied ? "取消列表" : "列表")
        updateFormattingControls()
        markDirty()
    }

    private func simpleListPrefix(in paragraphRange: NSRange,
                                  string: NSString) -> SimpleListPrefix? {
        guard paragraphRange.length > 0 else { return nil }
        let line = string.substring(with: paragraphRange) as NSString
        if line.length >= 2 {
            let first = line.character(at: 0)
            let second = line.character(at: 1)
            if (first == 0x2022 || first == 0x00B7) && second == 0x20 {
                return SimpleListPrefix(range: NSRange(location: paragraphRange.location, length: 2),
                                        numbered: false)
            }
        }
        var digits = 0
        while digits < line.length {
            let value = line.character(at: digits)
            guard value >= 48 && value <= 57 else { break }
            digits += 1
        }
        if digits > 0, digits + 1 < line.length,
           line.character(at: digits) == 0x2E,
           line.character(at: digits + 1) == 0x20 {
            return SimpleListPrefix(range: NSRange(location: paragraphRange.location,
                                                   length: digits + 2), numbered: true)
        }
        return nil
    }

    /// Apply a paragraph-style + attribute transform to every paragraph in range.
    private func applyToParagraphs(_ transform: (NSParagraphStyle?) -> (NSParagraphStyle, [NSAttributedString.Key: Any])) {
        guard let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        let string = (textView.string as NSString)
        let lineRange = string.lineRange(for: range)
        storage.beginEditing()
        enumerateParagraphRanges(in: lineRange) { paraRange in
            let existing = storage.attribute(.paragraphStyle, at: paraRange.location, effectiveRange: nil) as? NSParagraphStyle
            let (para, extra) = transform(existing)
            var attrs: [NSAttributedString.Key: Any] = [.paragraphStyle: para]
            attrs.merge(extra) { _, new in new }
            for (k, v) in attrs {
                storage.addAttribute(k, value: v, range: paraRange)
            }
        }
        storage.endEditing()
    }

    private func enumerateParagraphRanges(in range: NSRange, block: (NSRange) -> Void) {
        let string = (textView.string as NSString)
        var loc = range.location
        let end = NSMaxRange(range)
        while loc < end {
            let line = string.lineRange(for: NSRange(location: loc, length: 0))
            block(line)
            loc = NSMaxRange(line)
            if line.length == 0 { loc += 1 }
        }
    }

    // MARK: - Table helpers

    /// Older notes may contain the web editor's 1.7 line-height paragraph
    /// style. Normalize it when opening so existing notes use the same compact
    /// native rhythm as newly typed text, while preserving fonts, lists,
    /// spacing, and table blocks.
    private func normalizeLoadedParagraphStyles() {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let full = NSRange(location: 0, length: storage.length)
        var updates: [(NSRange, NSMutableParagraphStyle)] = []
        storage.enumerateAttribute(.paragraphStyle, in: full, options: []) { value, range, _ in
            guard let style = value as? NSParagraphStyle,
                  let paragraph = style.mutableCopy() as? NSMutableParagraphStyle else { return }
            paragraph.lineHeightMultiple = Theme.editorLineHeightMultiple
            paragraph.minimumLineHeight = 0
            paragraph.maximumLineHeight = 0
            updates.append((range, paragraph))
        }
        guard !updates.isEmpty else { return }
        storage.beginEditing()
        for (range, paragraph) in updates {
            storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
        }
        storage.endEditing()
    }

    private func currentTable() -> NSTextTable? {
        guard let storage = textView.textStorage else { return nil }
        guard storage.length > 0 else { return nil }
        var loc = textView.selectedRange().location
        if loc >= storage.length { loc = storage.length - 1 }
        if let ps = storage.attribute(.paragraphStyle, at: loc, effectiveRange: nil) as? NSParagraphStyle,
           let block = ps.textBlocks.first(where: { $0 is NSTextTableBlock }) as? NSTextTableBlock {
            return block.table
        }
        return nil
    }

    private struct CellInfo { let range: NSRange; let row: Int; let col: Int; let block: NSTextTableBlock }

    private func tableCells(for table: NSTextTable) -> [CellInfo] {
        var cells: [CellInfo] = []
        guard let storage = textView.textStorage else { return cells }
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.paragraphStyle, in: full, options: []) { value, r, _ in
            guard let ps = value as? NSParagraphStyle else { return }
            guard let block = ps.textBlocks.first(where: { ($0 as? NSTextTableBlock)?.table === table }) as? NSTextTableBlock else { return }
            cells.append(CellInfo(range: r, row: block.startingRow, col: block.startingColumn, block: block))
        }
        return cells.sorted { $0.range.location < $1.range.location }
    }

    private func tableRange(for table: NSTextTable) -> NSRange? {
        let cells = tableCells(for: table)
        guard let first = cells.first, let last = cells.last else { return nil }
        return NSRange(location: first.range.location,
                       length: NSMaxRange(last.range) - first.range.location)
    }

    /// Read the table as a small attributed matrix. Every table cell is a
    /// separate paragraph; this is the representation AppKit's text system
    /// expects and it keeps row/column mutations deterministic.
    private func tableGrid(for table: NSTextTable) -> [[NSAttributedString]]? {
        guard let storage = textView.textStorage else { return nil }
        let cells = tableCells(for: table)
        guard !cells.isEmpty else { return nil }
        let rowCount = (cells.map { $0.row }.max() ?? 0) + 1
        let colCount = max(table.numberOfColumns, (cells.map { $0.col }.max() ?? 0) + 1)
        let empty = NSAttributedString(string: "")
        var grid = Array(repeating: Array(repeating: empty, count: colCount), count: rowCount)
        let string = storage.string as NSString
        for cell in cells {
            var contentRange = cell.range
            if contentRange.length > 0,
               string.character(at: NSMaxRange(contentRange) - 1) == 10 {
                contentRange.length -= 1 // the final newline belongs to the cell paragraph
            }
            grid[cell.row][cell.col] = contentRange.length == 0
                ? empty
                : storage.attributedSubstring(from: contentRange)
        }
        return grid
    }

    private func defaultCellParagraph() -> NSMutableParagraphStyle {
        let p = (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        p.lineHeightMultiple = Theme.editorLineHeightMultiple
        return p
    }

    private func plainParagraphSeparator(font: NSFont = Theme.bodyFont) -> NSAttributedString {
        let p = (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        p.textBlocks = []
        p.lineHeightMultiple = Theme.editorLineHeightMultiple
        return NSAttributedString(string: "\n", attributes: [
            .font: font,
            .foregroundColor: Theme.text,
            .paragraphStyle: p,
        ])
    }

    private func buildTable(from rows: [[NSAttributedString]])
        -> (content: NSMutableAttributedString, starts: [[Int]]) {
        let rowCount = max(rows.count, 1)
        let colCount = max(rows.map { $0.count }.max() ?? 1, 1)
        let table = NSTextTable()
        table.numberOfColumns = colCount
        // Use one shared, hairline border between adjacent cells. Drawing a
        // full 1pt border on both sides with collapsesBorders=false makes each
        // grid line look twice as thick.
        let tableBorderWidth = CGFloat(0.5)
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        table.setWidth(tableBorderWidth, type: .absoluteValueType, for: .border)
        table.setBorderColor(Theme.border)

        let empty = NSAttributedString(string: "")
        let content = NSMutableAttributedString()
        var starts: [[Int]] = []
        for row in 0..<rowCount {
            var rowStarts: [Int] = []
            for col in 0..<colCount {
                let cellContent = col < rows[row].count ? rows[row][col] : empty
                let start = content.length
                rowStarts.append(start)
                if cellContent.length > 0 {
                    content.append(cellContent)
                }
                content.append(NSAttributedString(string: "\n", attributes: [
                    .font: Theme.bodyFont,
                    .foregroundColor: Theme.text
                ]))

                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1,
                                              startingColumn: col, columnSpan: 1)
                block.backgroundColor = row == 0 ? Theme.elevated : Theme.panel
                block.setWidth(tableBorderWidth, type: .absoluteValueType, for: .border)
                block.setBorderColor(Theme.border)
                let paragraph = (cellContent.length > 0
                    ? (cellContent.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                    : nil) ?? defaultCellParagraph()
                paragraph.textBlocks = [block]
                content.addAttribute(.paragraphStyle, value: paragraph,
                                     range: NSRange(location: start, length: content.length - start))
                if row == 0 && cellContent.length > 0 {
                    let bold = NSFontManager.shared.convert(Theme.bodyFont, toHaveTrait: .boldFontMask)
                    content.addAttribute(.font, value: bold,
                                         range: NSRange(location: start, length: cellContent.length))
                }
            }
            starts.append(rowStarts)
        }
        return (content, starts)
    }

    private func replaceSelectionWithTable(rows: [[NSAttributedString]], selection: NSRange) {
        guard let storage = textView.textStorage else { return }
        let maxLength = storage.length
        let start = min(max(selection.location, 0), maxLength)
        let end = min(max(NSMaxRange(selection), start), maxLength)
        let replaceRange = NSRange(location: start, length: end - start)
        let source = storage.string as NSString
        let needsPrefix = start > 0 && source.character(at: start - 1) != 10
        let needsSuffix = end < maxLength && source.character(at: end) != 10
        let built = buildTable(from: rows)
        let replacement = NSMutableAttributedString()
        if needsPrefix { replacement.append(NSAttributedString(string: "\n")) }
        let tableStart = start + replacement.length
        replacement.append(built.content)
        // A table cell's terminating newline belongs to the NSTextTableBlock.
        // At the end of a document, add a second, plain paragraph so the user
        // can click/type below the table instead of editing its last cell.
        let hasFollowingParagraph = end < maxLength && source.character(at: end) == 10
        if needsSuffix || !hasFollowingParagraph {
            replacement.append(plainParagraphSeparator())
        }
        storage.replaceCharacters(in: replaceRange, with: replacement)
        textView.setSelectedRange(NSRange(location: min(tableStart, storage.length), length: 0))
    }

    /// AppKit keeps a newline typed at the end of an NSTextTableBlock inside
    /// the table. When the caret is at the end of the final cell and there is
    /// no ordinary paragraph after the table, create that paragraph explicitly
    /// and move the caret into it.
    func editorShouldExitTableOnNewline(_ textView: EditorTextView) -> Bool {
        guard let storage = textView.textStorage,
              let table = currentTable(),
              let lastCell = tableCells(for: table).max(by: { $0.range.location < $1.range.location }) else {
            return false
        }
        let selection = textView.selectedRange()
        guard selection.length == 0,
              selection.location >= max(lastCell.range.location, NSMaxRange(lastCell.range) - 1) else {
            return false
        }

        let insertLocation = NSMaxRange(lastCell.range)
        if insertLocation < storage.length,
           let style = storage.attribute(.paragraphStyle, at: insertLocation, effectiveRange: nil) as? NSParagraphStyle,
           style.textBlocks.contains(where: { $0 is NSTextTableBlock }) {
            return false
        }

        if insertLocation == storage.length {
            storage.insert(plainParagraphSeparator(), at: insertLocation)
        }
        let plain = (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        plain.textBlocks = []
        plain.lineHeightMultiple = Theme.editorLineHeightMultiple
        textView.typingAttributes = [
            .font: Theme.bodyFont,
            .foregroundColor: Theme.text,
            .paragraphStyle: plain,
        ]
        textView.setSelectedRange(NSRange(location: insertLocation, length: 0))
        textView.didChangeText()
        return true
    }

    /// Keep Return inside a non-empty code paragraph. A second Return on an
    /// empty code paragraph exits the code block and starts normal text.
    func editorShouldExitCodeOnNewline(_ textView: EditorTextView) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }
        let string = storage.string as NSString
        let selectionLocation = min(max(selection.location, 0), storage.length)
        // `lineRange` at the end of a string returns the empty paragraph after
        // a trailing newline. Without a trailing newline, use the last
        // character so a non-empty final code line remains a code line.
        let lineLocation = selectionLocation == storage.length
            && string.character(at: storage.length - 1) != 10
            ? storage.length - 1
            : selectionLocation
        let paragraphRange = string.lineRange(for: NSRange(location: lineLocation, length: 0))
        guard paragraphIsCode(paragraphRange, storage: storage) else { return false }

        let contentEnd: Int
        if paragraphRange.length > 0,
           string.character(at: NSMaxRange(paragraphRange) - 1) == 10 {
            contentEnd = NSMaxRange(paragraphRange) - 1
        } else {
            contentEnd = NSMaxRange(paragraphRange)
        }
        guard selection.location >= contentEnd else { return false }

        let contentRange = NSRange(location: paragraphRange.location,
                                    length: max(0, contentEnd - paragraphRange.location))
        let content = string.substring(with: contentRange)
        guard content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Make the following newline and line explicitly code-styled;
            // AppKit otherwise may reuse a stale plain-text typing attribute.
            let paragraph = (storage.attribute(.paragraphStyle,
                                               at: max(paragraphRange.location,
                                                       min(contentEnd - 1, storage.length - 1)),
                                               effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy()
                as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.textBlocks = []
            paragraph.lineHeightMultiple = Theme.editorLineHeightMultiple
            textView.typingAttributes = [
                .font: Theme.monoFont,
                .foregroundColor: Theme.text,
                .backgroundColor: Theme.codeBackground,
                .paragraphStyle: paragraph,
            ]
            return false
        }

        let insertLocation = NSMaxRange(paragraphRange)
        storage.insert(plainParagraphSeparator(), at: insertLocation)
        let plain = (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        plain.textBlocks = []
        plain.lineHeightMultiple = Theme.editorLineHeightMultiple
        textView.typingAttributes = [
            .font: Theme.bodyFont,
            .foregroundColor: Theme.text,
            .paragraphStyle: plain,
        ]
        textView.setSelectedRange(NSRange(location: insertLocation, length: 0))
        textView.didChangeText()
        return true
    }

    /// A heading is a paragraph format, not a character-format mode. Return
    /// should therefore create a normal paragraph after it instead of letting
    /// NSTextView copy the H1 font and paragraph style into the next line.
    /// Keep the heading's font family, but return to the normal body size and
    /// remove bold so the user can immediately choose a different font/size.
    func editorShouldExitHeadingOnNewline(_ textView: EditorTextView) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }

        let string = storage.string as NSString
        let selectionLocation = min(max(selection.location, 0), storage.length)
        let lineLocation = selectionLocation == storage.length
            && string.character(at: storage.length - 1) != 10
            ? storage.length - 1
            : selectionLocation
        let paragraphRange = string.lineRange(for: NSRange(location: lineLocation, length: 0))
        let attributeLocation = min(paragraphRange.location, storage.length - 1)
        let attributes = storage.attributes(at: attributeLocation, effectiveRange: nil)
        let headingSize: CGFloat?
        switch Int(((attributes[.font] as? NSFont)?.pointSize ?? 0).rounded()) {
        case 24: headingSize = isHeadingAttributes(attributes, size: 24) ? 24 : nil
        case 20: headingSize = isHeadingAttributes(attributes, size: 20) ? 20 : nil
        case 18: headingSize = isHeadingAttributes(attributes, size: 18) ? 18 : nil
        case 16: headingSize = isHeadingAttributes(attributes, size: 16) ? 16 : nil
        case 14: headingSize = isHeadingAttributes(attributes, size: 14) ? 14 : nil
        default: headingSize = nil
        }
        guard headingSize != nil else { return false }

        let contentEnd: Int
        if paragraphRange.length > 0,
           string.character(at: NSMaxRange(paragraphRange) - 1) == 10 {
            contentEnd = NSMaxRange(paragraphRange) - 1
        } else {
            contentEnd = NSMaxRange(paragraphRange)
        }
        guard selection.location >= contentEnd else { return false }

        let headingFont = (attributes[.font] as? NSFont) ?? Theme.bodyFont
        let body = bodyFont(from: headingFont)
        let insertionLocation = min(selection.location, storage.length)
        storage.insert(plainParagraphSeparator(font: body), at: insertionLocation)

        let plain = (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        plain.textBlocks = []
        plain.lineHeightMultiple = Theme.editorLineHeightMultiple
        textView.typingAttributes = [
            .font: body,
            .foregroundColor: Theme.text,
            .paragraphStyle: plain,
        ]
        textView.setSelectedRange(NSRange(location: min(insertionLocation + 1, storage.length), length: 0))
        textView.didChangeText()
        return true
    }

    private func replaceTable(_ table: NSTextTable, with rows: [[NSAttributedString]],
                              selecting selection: (row: Int, col: Int)? = nil) {
        guard let storage = textView.textStorage,
              let range = tableRange(for: table) else { return }
        let built = buildTable(from: rows)
        storage.replaceCharacters(in: range, with: built.content)
        let row = min(max(selection?.row ?? 0, 0), built.starts.count - 1)
        let col = min(max(selection?.col ?? 0, 0), built.starts[row].count - 1)
        let location = range.location + built.starts[row][col]
        textView.setSelectedRange(NSRange(location: min(location, storage.length), length: 0))
    }

    private func mutateRow(before: Bool) {
        guard let table = currentTable(),
              let block = currentTableBlock(),
              var rows = tableGrid(for: table) else { return }
        let columns = max(rows.map { $0.count }.max() ?? 1, 1)
        let empty = NSAttributedString(string: "")
        let target = min(max(block.startingRow + (before ? 0 : 1), 0), rows.count)
        rows.insert(Array(repeating: empty, count: columns), at: target)
        replaceTable(table, with: rows, selecting: (target, min(block.startingColumn, columns - 1)))
        markDirty()
    }

    private func mutateColumn(before: Bool) {
        guard let table = currentTable(),
              let block = currentTableBlock(),
              var rows = tableGrid(for: table) else { return }
        let columns = max(rows.map { $0.count }.max() ?? 1, 1)
        let empty = NSAttributedString(string: "")
        let target = min(max(block.startingColumn + (before ? 0 : 1), 0), columns)
        for row in rows.indices {
            if rows[row].count < columns {
                rows[row].append(contentsOf: Array(repeating: empty, count: columns - rows[row].count))
            }
            rows[row].insert(empty, at: target)
        }
        replaceTable(table, with: rows, selecting: (min(block.startingRow, rows.count - 1), target))
        markDirty()
    }

    private func removeRow() {
        guard let table = currentTable(),
              let block = currentTableBlock(),
              var rows = tableGrid(for: table) else { return }
        if rows.count <= 1 { deleteTable(nil); return }
        let row = min(max(block.startingRow, 0), rows.count - 1)
        rows.remove(at: row)
        replaceTable(table, with: rows, selecting: (min(row, rows.count - 1), block.startingColumn))
        markDirty()
    }

    private func removeColumn() {
        guard let table = currentTable(),
              let block = currentTableBlock(),
              var rows = tableGrid(for: table) else { return }
        let columns = max(rows.map { $0.count }.max() ?? 1, 1)
        if columns <= 1 { deleteTable(nil); return }
        let col = min(max(block.startingColumn, 0), columns - 1)
        for row in rows.indices where col < rows[row].count {
            rows[row].remove(at: col)
        }
        replaceTable(table, with: rows, selecting: (min(block.startingRow, rows.count - 1), min(col, columns - 2)))
        markDirty()
    }

    private func currentTableBlock() -> NSTextTableBlock? {
        guard let storage = textView.textStorage, storage.length > 0 else { return nil }
        var loc = textView.selectedRange().location
        if loc >= storage.length { loc = storage.length - 1 }
        guard let ps = storage.attribute(.paragraphStyle, at: loc, effectiveRange: nil) as? NSParagraphStyle else {
            return nil
        }
        return ps.textBlocks.first(where: { $0 is NSTextTableBlock }) as? NSTextTableBlock
    }

    private func updateTableButtonStates() {
        let inTable = currentTable() != nil
        for b in tableOpButtons {
            b.isEnabled = inTable
            b.isHidden = !inTable
        }
    }

    // MARK: - Dirty / autosave

    private func markDirty() {
        guard !suppressChange else { return }
        dirty = true
        saveTimer?.invalidate()
        let t = Timer(timeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.flush()
        }
        RunLoop.main.add(t, forMode: .common)
        saveTimer = t
    }

    /// Preserve the loaded paragraph's indentation/list/code attributes when
    /// the caret becomes active. Replacing them with the plain default style
    /// makes an existing paragraph jump horizontally on the first edit.
    private func syncTypingAttributesWithCurrentParagraph() {
        guard let storage = textView.textStorage,
              storage.length > 0,
              textView.selectedRange().length == 0 else { return }
        let location = min(textView.selectedRange().location, storage.length - 1)
        textView.typingAttributes = storage.attributes(at: location, effectiveRange: nil)
    }
}

// MARK: - EditorTextViewDelegate

extension EditorViewController: EditorTextViewDelegate {
    func editorDidChange(_ textView: EditorTextView) {
        if let storage = textView.textStorage, storage.length > 0 {
            let location = min(textView.selectedRange().location, storage.length - 1)
            let paragraphRange = (storage.string as NSString).lineRange(
                for: NSRange(location: location, length: 0))
            if paragraphIsCode(paragraphRange, storage: storage) {
                highlightCode(in: paragraphRange, storage: storage)
            }
        }
        updateEditorDocumentSize()
        markDirty()
    }
    func editorRequestsSave(_ textView: EditorTextView, userInitiated: Bool) {
        flush(userInitiated: userInitiated)
    }
    func editorRequestsHide(_ textView: EditorTextView) {
        flush()
        delegate?.editorRequestsHide()
    }
}

// MARK: - NSTextViewDelegate (selection → table button states)

extension EditorViewController: NSTextViewDelegate {
    func textViewDidChangeSelection(_ notification: Notification) {
        syncTypingAttributesWithCurrentParagraph()
        updateFormattingControls()
        updateTableButtonStates()
    }
}

// MARK: - Toolbar button

/// Borderless toolbar button mirroring `.tb-btn`: transparent until hover/active.
class ToolbarButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false
    private(set) var isActive = false

    init(title: String, target: Any?, action: Selector) {
        super.init(frame: .zero)
        self.title = title
        self.target = target as? AnyObject
        self.action = action
        isBordered = false
        bezelStyle = .inline
        imagePosition = .noImage
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = Theme.buttonCornerRadius
    }
    required init?(coder: NSCoder) { fatalError() }

    func setActive(_ active: Bool) {
        isActive = active
        updateToolbarAppearance()
    }

    private func updateToolbarAppearance() {
        let highlighted = isHovered || isActive
        layer?.backgroundColor = highlighted ? Theme.accentSoft.cgColor : NSColor.clear.cgColor
        contentTintColor = highlighted ? Theme.accent : Theme.textDim
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateToolbarAppearance()
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateToolbarAppearance()
    }
}

/// A compact text menu control for the toolbar. The system popup control brings
/// along large up/down arrows and an inconsistent bezel. This keeps the same
/// flat hover behavior as the icon buttons and uses one small,
/// directional chevron to make the control read as a menu.
final class ToolbarMenuButton: ToolbarButton {
    private var titleLabel: NSTextField!
    private var chevronView: NSImageView!
    private(set) var menuTitle: String = ""

    override init(title: String, target: Any?, action: Selector) {
        super.init(title: "", target: target, action: action)
        font = NSFont.systemFont(ofSize: 12, weight: .medium)
        contentTintColor = Theme.textDim

        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = font
        titleLabel.textColor = Theme.textDim
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        // The button has a fixed compact width. Let the label compress and
        // show an ellipsis instead of reserving space for long font families.
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        chevronView = NSImageView()
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.contentTintColor = Theme.textDim
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        if let chevron = NSImage(systemSymbolName: "chevron.down",
                                  accessibilityDescription: "展开") {
            chevron.isTemplate = true
            chevronView.image = chevron.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        }
        let group = NSStackView(views: [titleLabel, chevronView])
        group.orientation = .horizontal
        group.alignment = .centerY
        group.spacing = 3
        group.setContentHuggingPriority(.required, for: .horizontal)
        group.translatesAutoresizingMaskIntoConstraints = false
        addSubview(group)
        NSLayoutConstraint.activate([
            group.centerXAnchor.constraint(equalTo: centerXAnchor),
            group.centerYAnchor.constraint(equalTo: centerYAnchor),
            group.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            group.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            chevronView.widthAnchor.constraint(equalToConstant: 10),
            chevronView.heightAnchor.constraint(equalToConstant: 10),
        ])
        setMenuTitle(title)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setMenuTitle(_ title: String) {
        menuTitle = title
        titleLabel.stringValue = title
        setAccessibilityLabel(title)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        titleLabel.textColor = Theme.accent
        chevronView.contentTintColor = Theme.accent
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        let color = isActive ? Theme.accent : Theme.textDim
        titleLabel.textColor = color
        chevronView.contentTintColor = color
    }

    override func setActive(_ active: Bool) {
        super.setActive(active)
        let color = active ? Theme.accent : Theme.textDim
        titleLabel.textColor = color
        chevronView.contentTintColor = color
    }
}

/// NSTextView is not horizontally scrollable in this editor. The default
/// clip view may nevertheless move its bounds origin briefly while the text
/// view becomes first responder, which is perceived as a left-margin jump.
/// Keep only the vertical origin under AppKit's control.
private final class EditorClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBoundsRect: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBoundsRect)
        bounds.origin.x = 0
        return bounds
    }
}
