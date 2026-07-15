import AppKit

protocol EditorTextViewDelegate: AnyObject {
    func editorDidChange(_ textView: EditorTextView)
    func editorRequestsSave(_ textView: EditorTextView, userInitiated: Bool)
    func editorRequestsHide(_ textView: EditorTextView)
    func editorShouldExitTableOnNewline(_ textView: EditorTextView) -> Bool
    func editorShouldExitCodeOnNewline(_ textView: EditorTextView) -> Bool
    func editorShouldExitHeadingOnNewline(_ textView: EditorTextView) -> Bool
}

/// A rich NSTextView that:
/// - accepts pasted/dragged images as embedded NSTextAttachments (saved inside
///   the RTFD package on write),
/// - forwards Esc (hide) and Cmd+S (save) through a delegate.
class EditorTextView: NSTextView {

    weak var editorDelegate: EditorTextViewDelegate?
    private var imagePreviewController: ImagePreviewWindowController?

    private static let imagePasteboardTypes: [(NSPasteboard.PasteboardType, String)] = [
        (.png, "png"),
        (.tiff, "tiff"),
        (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
        (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif"),
        (NSPasteboard.PasteboardType("public.image"), "png"),
    ]

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    convenience init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        self.init(frame: .zero, textContainer: container)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isRichText = true
        allowsUndo = true
        importsGraphics = true
        allowsImageEditing = false
        usesFontPanel = false
        usesRuler = false
        drawsBackground = true
        backgroundColor = Theme.editorBackground
        textColor = Theme.text
        font = Theme.bodyFont
        insertionPointColor = Theme.accent
        isHorizontallyResizable = false
        isVerticallyResizable = true
        // Keep the textContainer width synced to the text view's frame width.
        // Combined with autoresizingMask = [.width] (set when assembled into the
        // scroll view), this is what lets text wrap and reflow as the window
        // resizes; without it the container width stays 0 and nothing renders.
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.size = NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude)
        // lineFragmentPadding (default 5) counts toward the left inset, so a
        // width inset of 19 yields ~24px on both sides. Keep the vertical
        // rhythm compact enough for a native editor instead of the old 1.7x
        // web-editor spacing.
        textContainerInset = NSSize(width: 19, height: 14)
        textContainer?.lineFragmentPadding = 5
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = Theme.editorLineHeightMultiple
        defaultParagraphStyle = para
        typingAttributes = [.font: Theme.bodyFont,
                            .foregroundColor: Theme.text,
                            .paragraphStyle: para]
        smartInsertDeleteEnabled = false
        registerForDraggedTypes([.png, .tiff, .fileURL, .string,
                                 NSPasteboard.PasteboardType("public.jpeg"),
                                 NSPasteboard.PasteboardType("com.compuserve.gif"),
                                 NSPasteboard.PasteboardType("public.image")])
    }

    // MARK: - Image layout and preview

    /// Keep every embedded image inside the editor's actual text column. This
    /// also repairs older notes whose RTFD attachment retained a width larger
    /// than the current window.
    func fitEmbeddedImagesToAvailableWidth() {
        guard let storage = textStorage,
              let layoutManager,
              let textContainer,
              storage.length > 0 else { return }

        let maxWidth = availableImageWidth
        guard maxWidth > 1 else { return }

        var changed = false
        var imageParagraphs: [NSRange: NSMutableParagraphStyle] = [:]
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  let image = self.image(for: attachment),
                  image.size.width > 0,
                  image.size.height > 0 else { return }

            if attachment.image == nil {
                attachment.image = image
                changed = true
                layoutManager.invalidateLayout(forCharacterRange: range,
                                               actualCharacterRange: nil)
            }
            let fitted = self.fittedBounds(for: image, maxWidth: maxWidth)
            if attachment.bounds != fitted {
                attachment.bounds = fitted
                changed = true
                layoutManager.invalidateLayout(forCharacterRange: range,
                                               actualCharacterRange: nil)
            }

            // Pasted images can inherit the paragraph style of the text
            // before them. In particular, an image following a heading may
            // retain that heading's paragraph spacing and line-height, which
            // produces a large and unstable gap above the image after a note
            // is reopened. Collect the paragraph updates here and apply them
            // after enumeration so the text storage is never mutated from
            // inside its own attribute callback.
            let paragraphRange = (storage.string as NSString).paragraphRange(for: range)
            let paragraphLocation = min(paragraphRange.location, storage.length - 1)
            if let style = storage.attribute(.paragraphStyle,
                                             at: paragraphLocation,
                                             effectiveRange: nil) as? NSParagraphStyle,
               !style.textBlocks.contains(where: { $0 is NSTextTableBlock }),
               let paragraph = style.mutableCopy() as? NSMutableParagraphStyle {
                let needsTightSpacing = abs(style.paragraphSpacingBefore) > 0.01
                    || abs(style.paragraphSpacing) > 0.01
                    || abs(style.lineSpacing) > 0.01
                    || abs(style.lineHeightMultiple - 1) > 0.01
                    || abs(style.minimumLineHeight) > 0.01
                    || abs(style.maximumLineHeight) > 0.01
                guard needsTightSpacing else { return }
                paragraph.paragraphSpacingBefore = 0
                paragraph.paragraphSpacing = 0
                paragraph.lineSpacing = 0
                paragraph.lineHeightMultiple = 1
                paragraph.minimumLineHeight = 0
                paragraph.maximumLineHeight = 0
                imageParagraphs[paragraphRange] = paragraph
            }
        }

        if !imageParagraphs.isEmpty {
            storage.beginEditing()
            for (range, paragraph) in imageParagraphs {
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
                changed = true
            }
            storage.endEditing()
        }

        if changed {
            layoutManager.ensureLayout(for: textContainer)
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.buttonNumber == 0,
           event.clickCount == 1,
           let image = imageAtPoint(convert(event.locationInWindow, from: nil)) {
            imagePreviewController = ImagePreviewWindowController(image: image,
                                                                   screen: window?.screen)
            imagePreviewController?.showWindow(nil)
            imagePreviewController?.window?.makeKeyAndOrderFront(nil)
            return
        }
        super.mouseDown(with: event)
    }

    private var availableImageWidth: CGFloat {
        let viewWidth = bounds.width
        let containerWidth = textContainer?.size.width ?? viewWidth
        let width = min(viewWidth > 0 ? viewWidth : containerWidth, containerWidth)
        let padding = (textContainer?.lineFragmentPadding ?? 5) * 2
        // Leave a small, explicit trailing safety gap. AppKit attachment
        // glyphs can otherwise round up by a pixel and appear clipped against
        // the right edge when the editor width is fractional.
        let safetyGap: CGFloat = 24
        return max(100, width - textContainerInset.width * 2 - padding - safetyGap)
    }

    private func fittedBounds(for image: NSImage, maxWidth: CGFloat) -> NSRect {
        let scale = min(1, maxWidth / image.size.width)
        return NSRect(x: 0, y: 0,
                      width: floor(image.size.width * scale),
                      height: floor(image.size.height * scale))
    }

    private func image(for attachment: NSTextAttachment) -> NSImage? {
        if let image = attachment.image { return image }
        if let data = attachment.fileWrapper?.regularFileContents {
            return NSImage(data: data)
        }
        return nil
    }

    private func imageAtPoint(_ point: NSPoint) -> NSImage? {
        guard let storage = textStorage,
              let layoutManager,
              let textContainer,
              layoutManager.numberOfGlyphs > 0 else { return nil }

        let localPoint = NSPoint(x: point.x - textContainerOrigin.x,
                                 y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(
            for: localPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }

        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyph, length: 1),
            in: textContainer)
        guard glyphRect.insetBy(dx: -2, dy: -2).contains(localPoint) else { return nil }

        let character = layoutManager.characterIndexForGlyph(at: glyph)
        guard character >= 0, character < storage.length else { return nil }
        guard let attachment = storage.attribute(.attachment, at: character,
                                                  effectiveRange: nil) as? NSTextAttachment else {
            return nil
        }
        return image(for: attachment)
    }

    // MARK: - Keyboard equivalents

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Esc → hide
        if event.type == .keyDown, event.keyCode == 53 {
            editorDelegate?.editorRequestsHide(self)
            return true
        }
        // Cmd+S → save now
        if event.type == .keyDown, event.modifierFlags.contains(.command),
           let ch = event.charactersIgnoringModifiers, ch.lowercased() == "s" {
            editorDelegate?.editorRequestsSave(self, userInitiated: true)
            return true
        }
        if event.type == .keyDown, handleEditorShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if editorDelegate?.editorShouldExitTableOnNewline(self) == true {
            return
        }
        if editorDelegate?.editorShouldExitCodeOnNewline(self) == true {
            return
        }
        if editorDelegate?.editorShouldExitHeadingOnNewline(self) == true {
            return
        }
        super.insertNewline(sender)
    }

    override func keyDown(with event: NSEvent) {
        // A borderless floating panel does not always invoke
        // performKeyEquivalent before keyDown. Handle the same commands here
        // so undo/copy/paste work regardless of the current menu responder.
        if handleEditorShortcut(event) { return }
        super.keyDown(with: event)
    }

    /// Handle the editor's small, deliberately explicit shortcut set. Using
    /// key codes keeps this independent of the active keyboard layout, while
    /// the command path is shared by both AppKit keyboard entry points.
    private func handleEditorShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown,
              flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.option) else { return false }

        switch event.keyCode {
        case 0: // A
            guard !flags.contains(.shift) else { return false }
            selectAll(nil)
        case 8: // C
            guard !flags.contains(.shift) else { return false }
            copy(nil)
        case 7: // X
            guard !flags.contains(.shift) else { return false }
            cut(nil)
        case 9: // V
            guard !flags.contains(.shift) else { return false }
            // Route Cmd+V through the image-aware paste override first.
            paste(nil)
        case 6: // Z
            if flags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
        case 16: // Y
            guard !flags.contains(.shift) else { return false }
            undoManager?.redo()
        case 11: // B
            guard !flags.contains(.shift) else { return false }
            (editorDelegate as? EditorViewController)?.toggleBold(self)
        case 34: // I
            guard !flags.contains(.shift) else { return false }
            (editorDelegate as? EditorViewController)?.toggleItalic(self)
        default:
            return false
        }
        return true
    }

    // MARK: - Change notification

    override func didChangeText() {
        super.didChangeText()
        editorDelegate?.editorDidChange(self)
    }

    // MARK: - Placeholder (mirrors Editor.tsx Placeholder extension)

    /// Empty-editor hint, matching the Tauri placeholder
    /// "开始记录…  Cmd+S 保存，Esc 挂起". Drawn only while the text store is
    /// empty; any typed content (length > 0) suppresses it. Uses Theme.textDim
    /// and the body font so it stays in lock-step with the dark theme.
    private let placeholderString = "开始记录…  Cmd+S 保存，Esc 挂起"

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard textStorage?.length == 0 else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: Theme.textDim,
            .font: Theme.bodyFont,
        ]
        // textContainerOrigin already accounts for textContainerInset, so drawing
        // here aligns the placeholder with where the first typed character lands.
        (placeholderString as NSString).draw(at: textContainerOrigin, withAttributes: attrs)
    }

    // MARK: - Image paste / drop

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if insertImageFromPasteboard(pasteboard) {
            return
        }

        // Keep the rich-text attributes supplied by external apps, but do not
        // import their page/text background color into the dark editor.
        if let pasted = attributedTextFromPasteboard(pasteboard), pasted.length > 0 {
            let clean = NSMutableAttributedString(attributedString: pasted)
            clean.removeAttribute(.backgroundColor,
                                  range: NSRange(location: 0, length: clean.length))
            insertText(clean, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    private func attributedTextFromPasteboard(_ pasteboard: NSPasteboard) -> NSAttributedString? {
        let formats: [(NSPasteboard.PasteboardType, NSAttributedString.DocumentType)] = [
            (.rtfd, .rtfd),
            (.rtf, .rtf),
        ]
        for (type, documentType) in formats {
            if let data = pasteboard.data(forType: type),
               let attr = try? NSAttributedString(
                    data: data,
                    options: [.documentType: documentType],
                    documentAttributes: nil),
               attr.length > 0 {
                return attr
            }
        }

        let htmlType = NSPasteboard.PasteboardType("public.html")
        if let data = pasteboard.data(forType: htmlType),
           let attr = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil),
           attr.length > 0 {
            return attr
        }

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return NSAttributedString(string: string)
        }
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasImage(in: sender.draggingPasteboard) { return .copy }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if insertImageFromPasteboard(sender.draggingPasteboard) { return true }
        return super.performDragOperation(sender)
    }

    private func hasImage(in pb: NSPasteboard) -> Bool {
        if imageDataFromPasteboard(pb) != nil {
            return true
        }
        if NSImage(pasteboard: pb) != nil { return true }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           urls.contains(where: { isImageFile($0) }) {
            return true
        }
        return false
    }

    private func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "webp"].contains(ext)
    }

    @discardableResult
    private func insertImageFromPasteboard(_ pb: NSPasteboard) -> Bool {
        // 1) Prefer an image file URL — this lets us preserve the original bytes
        //    verbatim (no NSImage/tiffRepresentation round-trip that would
        //    re-encode everything to PNG). A file drag typically carries both a
        //    URL and an NSImage, so checking the URL first wins the fidelity
        //    race. Mirrors the Tauri `save_image` baseline, which keeps raw
        //    bytes and only normalizes the extension.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls where isImageFile(url) {
                if insertImageFromURL(url) { return true }
            }
        }
        // 2) Read the actual image bytes. Screenshots and images copied from
        // browsers commonly expose public.png/public.tiff but are not decoded
        // by NSImage(pasteboard:) on every macOS version.
        if let (data, ext) = imageDataFromPasteboard(pb),
           let image = NSImage(data: data) {
            return embedAttachment(data: data, ext: ext, baseName: "pasted",
                                   image: image)
        }
        // 3) Last-resort AppKit decoding for pasteboards that provide a
        // provider object rather than directly readable image bytes.
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return insertImage(image, suggestedName: "pasted.png")
        }
        if let image = NSImage(pasteboard: pb) {
            return insertImage(image, suggestedName: "pasted.png")
        }
        return false
    }

    private func imageDataFromPasteboard(_ pb: NSPasteboard) -> (data: Data, ext: String)? {
        // Prefer types with a known byte format. A generic public.image item
        // can contain TIFF bytes even when its UTI is not specific enough to
        // use as the attachment file type.
        for (type, ext) in Self.imagePasteboardTypes where type.rawValue != "public.image" {
            if let data = pb.data(forType: type), NSImage(data: data) != nil {
                return (data, ext)
            }
        }
        let generic = NSPasteboard.PasteboardType("public.image")
        if let data = pb.data(forType: generic),
           let image = NSImage(data: data),
           let png = encode(image, using: .png, properties: [:]) {
            return (png, "png")
        }
        return nil
    }

    /// Embed an image referenced by a file URL, preserving the original bytes.
    /// The extension is taken from the URL path (jpeg→jpg, png/gif/webp/svg/bmp
    /// as-is); unrecognized extensions fall back to a PNG re-encode so the
    /// filename stays consistent with the actual byte format (名实相符).
    @discardableResult
    func insertImageFromURL(_ url: URL) -> Bool {
        let rawExt = url.pathExtension.lowercased()
        switch rawExt {
        case "jpeg", "jpg", "png", "gif", "webp", "svg", "bmp":
            guard let data = try? Data(contentsOf: url) else { return false }
            let ext = rawExt == "jpeg" ? "jpg" : rawExt
            // NSImage is loaded only to size the attachment; the wrapper keeps
            // the raw bytes, so no re-encode happens on the saved content.
            let image = NSImage(contentsOf: url)
            return embedAttachment(data: data, ext: ext,
                                   baseName: (url.lastPathComponent as NSString).deletingPathExtension,
                                   image: image)
        default:
            // Unrecognized ext: re-encode to PNG and name it .png so filename
            // and byte format agree.
            guard let image = NSImage(contentsOf: url) else { return false }
            return insertImage(image, suggestedName: "image.png")
        }
    }

    /// Embed `image` as a file-wrapper attachment at the current selection.
    /// Used when only an NSImage is available (pasteboard paste, or a URL whose
    /// extension we can't preserve). Bytes are encoded per `suggestedName`'s
    /// extension: jpeg→.jpeg (0.9), png→.png, gif→.gif. Formats AppKit cannot
    /// encode (webp/heic) and vector SVG — which has no recoverable vector
    /// bytes via NSImage — degrade to PNG with a matching `.png` extension, so
    /// the filename always tracks the real byte format.
    @discardableResult
    func insertImage(_ image: NSImage, suggestedName: String) -> Bool {
        let rawExt = (suggestedName as NSString).pathExtension.lowercased()
        let ext: String
        let data: Data
        switch rawExt {
        case "jpeg", "jpg":
            guard let d = encode(image, using: .jpeg,
                                 properties: [.compressionFactor: 0.9]) else { return false }
            ext = "jpg"; data = d
        case "gif":
            guard let d = encode(image, using: .gif, properties: [:]) else { return false }
            ext = "gif"; data = d
        case "png":
            guard let d = encode(image, using: .png, properties: [:]) else { return false }
            ext = "png"; data = d
        default:
            // webp/heic (no encoder) and svg (no vector bytes via NSImage):
            // degrade to PNG, and switch the extension to png too.
            guard let d = encode(image, using: .png, properties: [:]) else { return false }
            ext = "png"; data = d
        }
        return embedAttachment(data: data, ext: ext,
                               baseName: (suggestedName as NSString).deletingPathExtension,
                               image: image)
    }

    /// Re-encode an NSImage to the requested bitmap type via tiffRepresentation.
    private func encode(_ image: NSImage, using type: NSBitmapImageRep.FileType,
                        properties: [NSBitmapImageRep.PropertyKey: Any]) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: type, properties: properties)
    }

    /// Build a stable native attachment from already-final bytes + extension
    /// and insert it at the current selection. Keeping the file wrapper for
    /// persistence while assigning the decoded NSImage explicitly avoids a
    /// macOS 26 AppKit crash in NSLayoutManager.showAttachment when it draws a
    /// raw `NSTextAttachment(data:ofType:)` created from pasteboard bytes.
    @discardableResult
    private func embedAttachment(data: Data, ext: String, baseName: String, image: NSImage?) -> Bool {
        guard let storage = textStorage else { return false }
        guard let image else { return false }

        let attachment = NSTextAttachment()
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = baseName.isEmpty ? "image.\(ext)" : "\(baseName).\(ext)"
        attachment.fileType = uti(for: ext)
        attachment.fileWrapper = wrapper
        // Set image after the wrapper: this is the object AppKit will draw,
        // while the wrapper remains the source persisted into the RTFD.
        attachment.image = image
        attachment.bounds = fittedBounds(for: image, maxWidth: availableImageWidth)
        let attrStr = NSAttributedString(attachment: attachment)
        let range = selectedRange()
        storage.replaceCharacters(in: range, with: attrStr)
        didChangeText()
        return true
    }

    /// Map a file extension to the UTI used for inline attachment rendering.
    private func uti(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "public.jpeg"
        case "gif": return "com.compuserve.gif"
        case "tiff", "tif": return "public.tiff"
        case "bmp": return "com.microsoft.bmp"
        case "webp": return "org.webmproject.webp"
        case "svg": return "public.svg-image"
        default: return "public.png"
        }
    }
}

/// Simple native image preview. The image is scaled down to the available
/// screen while preserving its aspect ratio; the editor itself remains
/// unchanged and the preview can be closed like any normal macOS window.
final class ImagePreviewWindowController: NSWindowController {
    init(image: NSImage, screen: NSScreen?) {
        let targetScreen = screen ?? NSScreen.main
        let screenFrame = targetScreen?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let screenSize = screenFrame.size
        let maxSize = NSSize(width: screenSize.width * 0.82,
                             height: screenSize.height * 0.82)
        let scale = min(1,
                        maxSize.width / max(image.size.width, 1),
                        maxSize.height / max(image.size.height, 1))
        let fitted = NSSize(width: image.size.width * scale,
                            height: image.size.height * scale)
        // Keep visible breathing room around the image. Sizing the window to
        // the exact fitted image dimensions lets AppKit round the image view
        // down by a pixel and clip the rightmost column of the bitmap.
        let windowSize = NSSize(width: max(360, fitted.width + 64),
                                height: max(260, fitted.height + 88))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "图片预览"
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.bg
        // The notes panel uses .popUpMenu so it can float over full-screen
        // applications. The preview must sit above that panel, otherwise a
        // click on an image can open a window that is immediately obscured.
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.bg.cgColor
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 4.0

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        scrollView.documentView = imageView
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        super.init(window: window)
        let initialScale = min(1,
                               maxSize.width / max(image.size.width, 1),
                               maxSize.height / max(image.size.height, 1))
        scrollView.magnification = max(0.1, initialScale)
        window.setFrameOrigin(NSPoint(x: screenFrame.midX - window.frame.width / 2,
                                      y: screenFrame.midY - window.frame.height / 2))
    }

    required init?(coder: NSCoder) { fatalError() }
}
