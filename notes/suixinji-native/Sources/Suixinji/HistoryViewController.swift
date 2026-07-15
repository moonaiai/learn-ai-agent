import AppKit

protocol HistoryViewControllerDelegate: AnyObject {
    func historyDidSelectNote(_ id: String)
    func historyDidDeleteNote(_ id: String)
    func historyDidMutate()
}

/// Global view (App.css `.history` / `.history-grid`): a card grid grouped by
/// category, mirroring `src/views/HistoryList.tsx`.
final class HistoryViewController: NSViewController {

    weak var delegate: HistoryViewControllerDelegate?

    private let store: NotesStore
    private var notes: [NoteMeta] = []
    private var categories: [Category] = []

    private struct Section { let category: Category?; let notes: [NoteMeta] }
    private var sections: [Section] = []

    private let flow = FlowView()
    private weak var historyScrollView: NSScrollView?

    init(store: NotesStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.bg.cgColor

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = flow
        // Keep the global card view scrollable with the wheel/trackpad, but do
        // not show a persistent scrollbar beside the cards.
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .automatic
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)

        // A scroll view owns its document view's frame. Keeping FlowView out of
        // Auto Layout avoids a constraint/layout pass while the panel is being
        // switched from the list view on macOS 26.
        flow.translatesAutoresizingMaskIntoConstraints = true
        flow.autoresizingMask = []
        flow.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
        flow.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        flow.spacing = NSSize(width: 12, height: 12)

        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        historyScrollView = scroll
        self.view = view
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let scroll = historyScrollView else { return }
        let width = max(scroll.contentView.bounds.width, 1)
        var bounds = scroll.contentView.bounds
        if abs(bounds.origin.x) > 0.5 {
            bounds.origin.x = 0
            scroll.contentView.setBoundsOrigin(bounds.origin)
        }
        if abs(flow.frame.minX) > 0.5 || abs(flow.frame.width - width) > 0.5 {
            flow.setFrameOrigin(NSPoint(x: 0, y: flow.frame.minY))
            flow.setFrameSize(NSSize(width: width, height: max(flow.frame.height, 1)))
            flow.needsLayout = true
        }
    }

    func reload(notes: [NoteMeta], categories: [Category]) {
        self.notes = notes
        self.categories = categories
        var byCat: [String: [NoteMeta]] = [:]
        var uncat: [NoteMeta] = []
        let known = Set(categories.map { $0.id })
        for n in notes {
            if n.category.isEmpty || !known.contains(n.category) { uncat.append(n) }
            else { byCat[n.category, default: []].append(n) }
        }
        sections = categories.map { Section(category: $0, notes: byCat[$0.id] ?? []) }
        if !uncat.isEmpty { sections.append(Section(category: nil, notes: uncat)) }
        buildCards()
    }

    private func buildCards() {
        flow.removeAllArrangedSubviews()

        if notes.isEmpty {
            let empty = EmptyStateView(icon: "🗒", text: "还没有笔记。切到 📋 列表开始记录吧。")
            flow.addArrangedSubview(empty, fullWidth: true)
            flow.needsLayout = true
            return
        }

        for sec in sections {
            let header = CategoryHeaderView(category: sec.category, count: sec.notes.count) { [weak self] event in
                guard let self = self else { return }
                switch event {
                case .rename(let name):
                    if let c = sec.category { self.store.upsertCategory(id: c.id, name: name) }
                    self.delegate?.historyDidMutate()
                case .delete:
                    if let c = sec.category {
                        self.store.deleteCategory(id: c.id)
                        self.delegate?.historyDidMutate()
                    }
                }
            }
            flow.addArrangedSubview(header, fullWidth: true)

            for note in sec.notes {
                let card = NoteCardView(note: note) { [weak self] event in
                    guard let self = self else { return }
                    switch event {
                    case .open(let id): self.delegate?.historyDidSelectNote(id)
                    case .delete(let id): self.delegate?.historyDidDeleteNote(id)
                    }
                }
                flow.addArrangedSubview(card, fullWidth: false)
            }
        }

        flow.needsLayout = true
    }
}

// MARK: - Flow layout

final class FlowView: NSView {
    var edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    var spacing = NSSize(width: 8, height: 8)

    private var items: [(view: NSView, fullWidth: Bool)] = []

    override var isFlipped: Bool { true }

    func addArrangedSubview(_ v: NSView, fullWidth: Bool) {
        v.translatesAutoresizingMaskIntoConstraints = true
        addSubview(v)
        items.append((v, fullWidth))
        needsLayout = true
    }

    func removeFromSuperview(_ v: NSView) {
        items.removeAll { $0.view === v }
        v.removeFromSuperview()
        needsLayout = true
    }

    func removeAllArrangedSubviews() {
        let oldItems = items
        items.removeAll()
        oldItems.forEach { $0.view.removeFromSuperview() }
        needsLayout = true
    }

    var arrangedSubviews: [NSView] { items.map { $0.view } }

    /// Keep four cards visible in the default panel width while still
    /// allowing narrower windows to fall back to three, two, or one column.
    private static let minCardWidth: CGFloat = 140
    private static let headerHeight: CGFloat = 28
    // The card contains an icon, up to two title lines, and a timestamp.
    // 96px was too short: the title could paint into the next grid row.
    private static let cardHeight: CGFloat = 120

    /// Responsive column layout mirroring CSS
    /// `grid-template-columns: repeat(auto-fill, minmax(160px, 1fr))`.
    /// The native view intentionally caps this at four columns; narrower
    /// windows use fewer columns and wider windows keep the same four-column
    /// rhythm. This keeps the global view vertically scrollable only.
    private func responsiveCardWidth(containerWidth width: CGFloat) -> CGFloat {
        let gap = spacing.width
        let minW = FlowView.minCardWidth
        let w = max(width, 0)
        var cols = min(4, max(1, Int(floor((w + gap) / (minW + gap)))))
        var cardWidth = (w - CGFloat(max(cols - 1, 0)) * gap) / CGFloat(max(cols, 1))
        while cols > 1 && cardWidth < minW {
            cols -= 1
            cardWidth = (w - CGFloat(max(cols - 1, 0)) * gap) / CGFloat(max(cols, 1))
        }
        return max(cardWidth, 0)
    }

    override func layout() {
        super.layout()
        let width = bounds.width - edgeInsets.left - edgeInsets.right
        let cardWidth = responsiveCardWidth(containerWidth: width)
        var x = edgeInsets.left
        var y = edgeInsets.top
        var rowHeight: CGFloat = 0

        for (view, fullWidth) in items {
            let size: NSSize
            if fullWidth {
                let height: CGFloat = view is EmptyStateView ? 120 : FlowView.headerHeight
                size = NSSize(width: max(width, 0), height: height)
            } else {
                size = NSSize(width: cardWidth, height: FlowView.cardHeight)
            }
            // A category header starts a new full-width section. Finish the
            // preceding card row first; otherwise the next section's cards
            // begin in the middle of the previous section.
            if fullWidth && rowHeight > 0 {
                y += rowHeight + spacing.height
                x = edgeInsets.left
                rowHeight = 0
            }
            if !fullWidth && x + size.width > edgeInsets.left + width + 0.5 {
                x = edgeInsets.left
                y += rowHeight + spacing.height
                rowHeight = 0
            }
            view.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            if fullWidth {
                x = edgeInsets.left
                y += size.height + spacing.height
                rowHeight = 0
            } else {
                x += size.width + spacing.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        let totalHeight = y + rowHeight + edgeInsets.bottom
        // NSScrollView bottom-anchors a document view that is shorter than its
        // clip view, which made the list appear at the bottom of the pane.
        // Grow the document to fill the clip's visible height so short content
        // stays top-aligned (FlowView is flipped, content starts at y=0).
        let clipHeight = superview?.bounds.height ?? 0
        let fullHeight = max(totalHeight, clipHeight)
        if abs(frame.size.height - fullHeight) > 0.5 {
            frame.size.height = fullHeight
        }
    }

    override var intrinsicContentSize: NSSize {
        let width = bounds.width - edgeInsets.left - edgeInsets.right
        let cardWidth = responsiveCardWidth(containerWidth: width)
        var x = edgeInsets.left, y = edgeInsets.top, rowHeight: CGFloat = 0
        for (_, fullWidth) in items {
            let w: CGFloat = fullWidth ? width : cardWidth
            let h: CGFloat = fullWidth ? FlowView.headerHeight : FlowView.cardHeight
            if fullWidth && rowHeight > 0 {
                y += rowHeight + spacing.height
                x = edgeInsets.left
                rowHeight = 0
            }
            if !fullWidth && x + w > edgeInsets.left + width + 0.5 {
                x = edgeInsets.left
                y += rowHeight + spacing.height
                rowHeight = 0
            }
            if fullWidth {
                x = edgeInsets.left
                y += h + spacing.height
                rowHeight = 0
            } else {
                x += w + spacing.width
                rowHeight = max(rowHeight, h)
            }
        }
        return NSSize(width: bounds.width, height: y + rowHeight + edgeInsets.bottom)
    }
}

// MARK: - Empty state

final class EmptyStateView: NSView {
    init(icon: String, text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        let iconLabel = NSTextField(labelWithString: icon)
        iconLabel.font = NSFont.systemFont(ofSize: 32)
        iconLabel.alignment = .center
        let textLabel = NSTextField(labelWithString: text)
        textLabel.font = NSFont.systemFont(ofSize: 14)
        textLabel.textColor = Theme.textDim
        textLabel.alignment = .center
        [iconLabel, textLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            iconLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            iconLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            textLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 8),
            textLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
        fittingSize = NSSize(width: 400, height: 120)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var fittingSize: NSSize {
        get { NSSize(width: 400, height: 120) }
        set { _ = newValue }
    }
}

// MARK: - Note card (App.css .note-card)

final class NoteCardView: NSView {
    enum Event { case open(String); case delete(String) }

    private let noteId: String
    private let onEvent: (Event) -> Void
    private var confirming = false { didSet { rebuildControls(); updateBorder() } }
    private var isHover = false { didSet { updateBorder(); controlsHidden = !(isHover || confirming) } }

    private let iconLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let controls = NSStackView()
    private let deleteBtn = SmallIconButton(title: "×", tooltip: "删除笔记")

    init(note: NoteMeta, onEvent: @escaping (Event) -> Void) {
        self.noteId = note.id
        self.onEvent = onEvent
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 120))
        clipsToBounds = true
        wantsLayer = true
        layer?.backgroundColor = Theme.elevated.cgColor
        layer?.cornerRadius = Theme.cardCornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = Theme.border.cgColor

        iconLabel.font = NSFont.systemFont(ofSize: 22)
        iconLabel.stringValue = note.icon
        iconLabel.textColor = Theme.text

        titleLabel.font = Theme.cardTitleFont
        titleLabel.textColor = Theme.text
        titleLabel.stringValue = note.title.isEmpty ? "无标题" : note.title
        titleLabel.maximumNumberOfLines = 2
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.cell?.wraps = true

        timeLabel.font = Theme.smallFont
        timeLabel.textColor = Theme.textDim
        timeLabel.stringValue = formatTime(note.mtime)

        controls.orientation = .horizontal
        controls.spacing = 4

        deleteBtn.font = NSFont.systemFont(ofSize: 15)
        deleteBtn.onActivate = { [weak self] in self?.confirming = true }

        let top = NSStackView()
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 8
        top.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        top.translatesAutoresizingMaskIntoConstraints = false
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        top.addArrangedSubview(iconLabel)
        top.addArrangedSubview(spacer)
        controls.addArrangedSubview(deleteBtn)
        top.addArrangedSubview(controls)

        [top, titleLabel, timeLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            top.leadingAnchor.constraint(equalTo: leadingAnchor),
            top.trailingAnchor.constraint(equalTo: trailingAnchor),
            top.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: timeLabel.topAnchor, constant: -4),

            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])

        rebuildControls()
        controls.isHidden = true

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
        installHoverTracker(on: self) { [weak self] hovered in self?.isHover = hovered }
    }
    required init?(coder: NSCoder) { fatalError() }

    private var controlsHidden = true { didSet { controls.isHidden = controlsHidden } }

    private func updateBorder() {
        if confirming { layer?.borderColor = Theme.danger.cgColor }
        else if isHover { layer?.borderColor = Theme.accent.cgColor }
        else { layer?.borderColor = Theme.border.cgColor }
    }

    private func rebuildControls() {
        controls.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if confirming {
            let yes = MiniButton(title: "删除", danger: true) { [weak self] in
                guard let self = self else { return }
                self.onEvent(.delete(self.noteId))
            }
            let no = MiniButton(title: "取消", filled: false) { [weak self] in self?.confirming = false }
            controls.addArrangedSubview(yes)
            controls.addArrangedSubview(no)
        } else {
            controls.addArrangedSubview(deleteBtn)
        }
    }

    @objc private func clicked() {
        if !confirming { onEvent(.open(noteId)) }
    }

    override var fittingSize: NSSize { NSSize(width: 180, height: 120) }
}
