import AppKit

enum MainViewState: String, Codable {
    case list
    case global
    case listHiddenSidebar = "list-hidden-sidebar"
}

struct StoredWindowFrame: Codable {
    let xPercent: Double?
    let yPercent: Double?
    // Kept only to read the absolute-pixel format written by the previous
    // version. The next user move/resize rewrites it in percentage form.
    let legacyX: Double?
    let legacyY: Double?
    let width: Double
    let height: Double

    private enum CodingKeys: String, CodingKey {
        case xPercent
        case yPercent
        case x
        case y
        case width
        case height
    }

    init(_ frame: NSRect, visibleFrame: NSRect) {
        let availableWidth = max(visibleFrame.width - frame.width, 1)
        let availableHeight = max(visibleFrame.height - frame.height, 1)
        xPercent = min(max((frame.minX - visibleFrame.minX) / availableWidth, 0), 1)
        yPercent = min(max((frame.minY - visibleFrame.minY) / availableHeight, 0), 1)
        legacyX = nil
        legacyY = nil
        width = frame.size.width
        height = frame.size.height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        xPercent = try container.decodeIfPresent(Double.self, forKey: .xPercent)
        yPercent = try container.decodeIfPresent(Double.self, forKey: .yPercent)
        legacyX = try container.decodeIfPresent(Double.self, forKey: .x)
        legacyY = try container.decodeIfPresent(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(xPercent, forKey: .xPercent)
        try container.encodeIfPresent(yPercent, forKey: .yPercent)
        if xPercent == nil {
            try container.encodeIfPresent(legacyX, forKey: .x)
        }
        if yPercent == nil {
            try container.encodeIfPresent(legacyY, forKey: .y)
        }
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }

    func nsRect(in visibleFrame: NSRect, fallbackSize: NSSize) -> NSRect {
        let resolvedWidth = width > 0 ? CGFloat(width) : fallbackSize.width
        let resolvedHeight = height > 0 ? CGFloat(height) : fallbackSize.height
        let availableWidth = max(visibleFrame.width - resolvedWidth, 0)
        let availableHeight = max(visibleFrame.height - resolvedHeight, 0)

        let x: CGFloat
        if let xPercent {
            x = visibleFrame.minX + CGFloat(min(max(xPercent, 0), 1)) * availableWidth
        } else if let legacyX {
            x = CGFloat(legacyX)
        } else {
            x = visibleFrame.midX - resolvedWidth / 2
        }

        let y: CGFloat
        if let yPercent {
            y = visibleFrame.minY + CGFloat(min(max(yPercent, 0), 1)) * availableHeight
        } else if let legacyY {
            y = CGFloat(legacyY)
        } else {
            y = visibleFrame.midY - resolvedHeight / 2
        }

        var frame = NSRect(x: x, y: y, width: resolvedWidth, height: resolvedHeight)
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
        return frame
    }
}

struct SuixinjiWindowConfiguration: Codable {
    var frame: StoredWindowFrame?
    var viewState: MainViewState
    var pinned: Bool

    init(frame: StoredWindowFrame? = nil,
         viewState: MainViewState = .list,
         pinned: Bool = false) {
        self.frame = frame
        self.viewState = viewState
        self.pinned = pinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frame = try container.decodeIfPresent(StoredWindowFrame.self, forKey: .frame)
        viewState = try container.decodeIfPresent(MainViewState.self, forKey: .viewState) ?? .list
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }
}

/// Persists window behavior beside the notes data. The file is deliberately
/// separate from note content so changing the editor never changes layout
/// preferences and the preferences remain easy to inspect or reset.
final class SuixinjiWindowConfigurationStore {
    private let url: URL
    private let writeQueue = DispatchQueue(label: "com.suixinji.window-config-write",
                                            qos: .utility)
    private(set) var value: SuixinjiWindowConfiguration

    init() {
        url = NotesStore.resolveNotesDir().appendingPathComponent("window-config.json")
        value = Self.load(from: url)
        migrateLegacyFrameIfNeeded()
    }

    func update(frame: NSRect) {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.main
        value.frame = StoredWindowFrame(frame,
                                        visibleFrame: screen?.visibleFrame
                                            ?? NSRect(x: 0, y: 0, width: 1, height: 1))
        save()
    }

    func update(viewState: MainViewState) {
        value.viewState = viewState
        save()
    }

    func update(pinned: Bool) {
        value.pinned = pinned
        save()
    }

    /// Restores the last frame when it is still usable. If a monitor was
    /// removed or the saved data is missing, use the centered first-launch
    /// frame instead. Position is restored as a percentage of the target
    /// screen's available travel area; the saved size remains in points.
    func restoredFrame(defaultFrame: NSRect) -> NSRect {
        guard let screen = NSScreen.main,
              value.frame != nil else { return defaultFrame }
        return frame(on: screen, fallbackSize: defaultFrame.size)
    }

    func frame(on screen: NSScreen, fallbackSize: NSSize) -> NSRect {
        value.frame?.nsRect(in: screen.visibleFrame, fallbackSize: fallbackSize)
            ?? NSRect(x: screen.visibleFrame.midX - fallbackSize.width / 2,
                      y: screen.visibleFrame.midY - fallbackSize.height / 2,
                      width: fallbackSize.width,
                      height: fallbackSize.height)
    }

    private func save() {
        let snapshot = value
        let targetURL = url
        let fileManager = FileManager.default
        writeQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? fileManager.createDirectory(at: targetURL.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
            try? data.write(to: targetURL, options: .atomic)
        }
    }

    private func migrateLegacyFrameIfNeeded() {
        guard let oldFrame = value.frame,
              let x = oldFrame.legacyX,
              let y = oldFrame.legacyY else { return }

        let legacy = NSRect(x: x,
                            y: y,
                            width: oldFrame.width,
                            height: oldFrame.height)
        let center = NSPoint(x: legacy.midX, y: legacy.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.main
        value.frame = StoredWindowFrame(legacy,
                                        visibleFrame: screen?.visibleFrame
                                            ?? NSRect(x: 0, y: 0, width: 1, height: 1))
        save()
    }

    private static func load(from url: URL) -> SuixinjiWindowConfiguration {
        guard let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(SuixinjiWindowConfiguration.self,
                                                            from: data) else {
            return SuixinjiWindowConfiguration()
        }
        return configuration
    }
}
