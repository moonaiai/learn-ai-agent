import AppKit
import WebKit
import UniformTypeIdentifiers

/// Weak bridge object so WKWebView does not retain the view controller through
/// its user-content-controller message handler.
private final class SuixinjiScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// WKWebView on macOS does not always expose an image clipboard item to the
/// DOM paste event. Intercept the AppKit paste action as a fallback and pass a
/// data URL into Tiptap, while forwarding ordinary text paste to WebKit.
private final class SuixinjiWebView: WKWebView {
    var onPasteboardPaste: (() -> Bool)?
    var onEditorShortcut: ((String) -> Bool)?

    private func handleCommandShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.option),
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if key == "v" {
            return onPasteboardPaste?() == true
        }
        switch key {
        case "a": return onEditorShortcut?("selectAll") == true
        case "c": return onEditorShortcut?("copy") == true
        case "x": return onEditorShortcut?("cut") == true
        case "f": return onEditorShortcut?("find") == true
        case "z": return onEditorShortcut?(flags.contains(.shift) ? "redo" : "undo") == true
        case "y": return onEditorShortcut?("redo") == true
        default: return false
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleCommandShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleCommandShortcut(event) { return }
        super.keyDown(with: event)
    }

    // The physical Cmd+V path can arrive as the responder-chain paste action
    // without going through performKeyEquivalent/keyDown (especially when
    // AppKit has a standard Edit > Paste command active). Handle that action
    // directly so image paste does not depend on which key-event branch won.
    override func tryToPerform(_ action: Selector, with object: Any?) -> Bool {
        switch NSStringFromSelector(action) {
        case "paste:":
            if onPasteboardPaste?() == true { return true }
        case "copy:":
            if onEditorShortcut?("copy") == true { return true }
        case "cut:":
            if onEditorShortcut?("cut") == true { return true }
        case "selectAll:":
            if onEditorShortcut?("selectAll") == true { return true }
        case "find:":
            if onEditorShortcut?("find") == true { return true }
        case "undo:":
            if onEditorShortcut?("undo") == true { return true }
        case "redo:":
            if onEditorShortcut?("redo") == true { return true }
        default:
            break
        }
        return super.tryToPerform(action, with: object)
    }

    static func imageDataURLFromPasteboard() -> String? {
        let pasteboard = NSPasteboard.general
        let declaredTypes = pasteboard.types?.map(\.rawValue) ?? []
        NSLog("[suixinji] pasteboard types: \(declaredTypes.joined(separator: ","))")

        // Different macOS applications publish different image flavors. Read
        // every declared UTI rather than relying on only png/tiff; screenshots
        // and browser images commonly arrive as public.jpeg, public.webp, or a
        // provider-specific image type.
        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types {
                guard let uti = UTType(type.rawValue), uti.conforms(to: .image),
                      let raw = item.data(forType: type),
                      let png = pngData(from: raw) else { continue }
                NSLog("[suixinji] image read from pasteboard type=\(type.rawValue) bytes=\(png.count)")
                return "data:image/png;base64,\(png.base64EncodedString())"
            }
        }

        // Some apps expose images only through NSPasteboard's object reader,
        // without publishing png/tiff data types directly.
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            NSLog("[suixinji] image read from NSPasteboard object bytes=\(png.count)")
            return "data:image/png;base64,\(png.base64EncodedString())"
        }

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) {
            for object in urls {
                guard let fileURL = object as? URL,
                      let type = UTType(filenameExtension: fileURL.pathExtension),
                      type.conforms(to: .image),
                      let raw = try? Data(contentsOf: fileURL),
                      let png = pngData(from: raw) else { continue }
                NSLog("[suixinji] image read from file URL bytes=\(png.count)")
                return "data:image/png;base64,\(png.base64EncodedString())"
            }
        }
        NSLog("[suixinji] no image found on pasteboard")
        return nil
    }

    private static func pngData(from raw: Data) -> Data? {
        if let bitmap = NSBitmapImageRep(data: raw),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return png
        }
        guard let image = NSImage(data: raw),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// Experimental editor backed by a local Tiptap/ProseMirror bundle.
///
/// This controller owns only the editor surface and its JSON bridge. The
/// native panel, sidebar, categories, keyboard shortcuts, and note lifecycle
/// remain AppKit code shared with the existing NSTextView implementation.
final class WKWebViewEditorViewController: NSViewController, NoteEditorController {

    weak var delegate: EditorViewControllerDelegate?

    private let store: NotesStore
    private var webView: SuixinjiWebView!
    private var messageHandler: SuixinjiScriptMessageHandler!
    private var pageReady = false
    private var pendingPayload: [String: Any]?
    private enum PendingPaste {
        case image(String)
        case html(String)
        case text(String)
    }
    private var pendingPaste: PendingPaste?
    private var latestDocument: Data?
    private var latestHTML: String?
    private var latestTitle = "无标题"
    private var saveTimer: Timer?
    private var dirty = false
    private var persisted = false
    private var meta: NoteMeta?
    private(set) var currentNoteId: String?
    private var imagePreviewController: ImagePreviewWindowController?
    private var searchVisible = false

    var hasUnsavedChanges: Bool { dirty }

    init(store: NotesStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.editorBackground.cgColor

        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        messageHandler = SuixinjiScriptMessageHandler(target: self)
        userContentController.add(messageHandler, name: "suixinji")
        configuration.userContentController = userContentController
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = SuixinjiWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.wantsLayer = true
        webView.layer?.backgroundColor = Theme.editorBackground.cgColor
        webView.onPasteboardPaste = { [weak self] in
            self?.handlePaste() ?? false
        }
        webView.onEditorShortcut = { [weak self] action in
            self?.handleEditorShortcut(action) ?? false
        }
        webView.navigationDelegate = self

        root.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.topAnchor.constraint(equalTo: root.topAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        self.view = root

        loadBundledEditor()
    }

    private func loadBundledEditor() {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: "index", withExtension: "html",
                              subdirectory: "dist"),
            Bundle.module.url(forResource: "index", withExtension: "html",
                              subdirectory: "WebEditor/dist"),
            Bundle.module.url(forResource: "index", withExtension: "html",
                              subdirectory: "WebEditor"),
            Bundle.module.url(forResource: "index", withExtension: "html"),
        ]
        guard let index = candidates.compactMap({ $0 }).first else {
            showLoadError("未找到 Web 编辑器资源，请先执行 WebEditor 构建")
            return
        }
        // Legacy HTML/RTFD notes can contain file-backed image references
        // outside the bundle. The document loader also converts known legacy
        // refs to data URLs, while this broader read root covers older notes
        // that still retain a file URL in their serialized content.
        webView.loadFileURL(index, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    private func showLoadError(_ message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.textColor = Theme.textDim
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - NoteEditorController

    func openNote(id: String) {
        if currentNoteId != id {
            flush(userInitiated: false)
        }
        currentNoteId = id
        meta = store.listNotes().first { $0.id == id }
            ?? NoteMeta(id: id, title: "无标题", icon: "📝", category: "",
                        mtime: Int(Date().timeIntervalSince1970))
        persisted = true
        dirty = false
        saveTimer?.invalidate()
        latestDocument = nil
        latestHTML = nil
        latestTitle = meta?.title ?? "无标题"
        pendingPayload = payloadForExistingNote(id)
        sendPendingPayloadIfReady()
        delegate?.editorSaveStatus("")
    }

    func newNote() {
        currentNoteId = newNoteId()
        meta = NoteMeta(id: currentNoteId ?? "", title: "", icon: "📝", category: "",
                        mtime: Int(Date().timeIntervalSince1970))
        persisted = false
        dirty = false
        saveTimer?.invalidate()
        latestTitle = "无标题"
        let emptyContent: [String: Any] = [
            "version": 1,
            "content": ["type": "doc", "content": [["type": "paragraph"]]]
        ]
        latestDocument = try? JSONSerialization.data(withJSONObject: emptyContent)
        latestHTML = "<p></p>"
        pendingPayload = emptyContent
        sendPendingPayloadIfReady()
        delegate?.editorSaveStatus("")
    }

    func flush(userInitiated: Bool = false) {
        guard let id = currentNoteId, let noteMeta = meta,
              dirty || (userInitiated && !persisted),
              let document = latestDocument else { return }

        var updated = noteMeta
        updated.title = latestTitle.isEmpty ? "无标题" : latestTitle
        store.saveWebNote(id: id, document: document, meta: updated, html: latestHTML)
        meta = updated
        persisted = true
        dirty = false
        saveTimer?.invalidate()
        let now = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        delegate?.editorSaveStatus(userInitiated ? "已保存 \(now)" : "已自动保存 \(now)")
        delegate?.noteMetaDidChange(id)
    }

    func focus() {
        guard pageReady else { return }
        view.window?.makeFirstResponder(webView)
        evaluate("window.SuixinjiEditor && window.SuixinjiEditor.focus();")
    }

    func openSearch() -> Bool {
        guard pageReady else { return false }
        searchVisible = true
        callEditorCommand("window.SuixinjiEditor && window.SuixinjiEditor.openSearch();")
        return true
    }

    func jumpToOutlineItem(_ index: Int) {
        guard pageReady, index >= 0 else { return }
        evaluate("window.SuixinjiEditor && window.SuixinjiEditor.jumpToOutline(\(index));")
    }

    private func insertPastedImage(_ dataURL: String) -> Bool {
        guard pageReady else {
            // The global Cmd+V monitor can run during the short interval in
            // which the panel is visible but the local HTML has not finished
            // loading. Queue the image instead of letting that paste vanish.
            pendingPaste = .image(dataURL)
            NSLog("[suixinji] queued image paste until web editor is ready")
            return true
        }
        // Do not interpolate base64 into JavaScript source. Large clipboard
        // images can exceed WebKit's script parsing limits and were also the
        // source of crashes during the old native HTML fallback save.
        webView.callAsyncJavaScript(
            "window.SuixinjiEditor && window.SuixinjiEditor.insertImage(imageData)",
            arguments: ["imageData": dataURL],
            in: nil,
            in: .page
        ) { result in
            if case .failure(let error) = result {
                NSLog("[suixinji] image paste bridge error: \(error)")
            }
        }
        return true
    }

    private func insertPastedHTML(_ html: String) -> Bool {
        guard pageReady else {
            pendingPaste = .html(html)
            return true
        }
        webView.callAsyncJavaScript(
            "window.SuixinjiEditor && window.SuixinjiEditor.insertHTML(pastedHTML)",
            arguments: ["pastedHTML": html],
            in: nil,
            in: .page
        ) { result in
            if case .failure(let error) = result {
                NSLog("[suixinji] html paste bridge error: \(error)")
            }
        }
        return true
    }

    private func insertPastedText(_ text: String) -> Bool {
        guard pageReady else {
            pendingPaste = .text(text)
            return true
        }
        webView.callAsyncJavaScript(
            "window.SuixinjiEditor && window.SuixinjiEditor.insertText(pastedText)",
            arguments: ["pastedText": text],
            in: nil,
            in: .page
        ) { result in
            if case .failure(let error) = result {
                NSLog("[suixinji] text paste bridge error: \(error)")
            }
        }
        return true
    }

    private func insertPendingPaste(_ paste: PendingPaste) -> Bool {
        switch paste {
        case .image(let dataURL): return insertPastedImage(dataURL)
        case .html(let html): return insertPastedHTML(html)
        case .text(let text): return insertPastedText(text)
        }
    }

    func handlePaste() -> Bool {
        let pasteboard = NSPasteboard.general
        if let dataURL = SuixinjiWebView.imageDataURLFromPasteboard() {
            return insertPastedImage(dataURL)
        }
        let htmlType = NSPasteboard.PasteboardType("public.html")
        if let html = pasteboard.string(forType: htmlType), !html.isEmpty {
            return insertPastedHTML(html)
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return insertPastedText(text)
        }
        return false
    }

    private func handleEditorShortcut(_ action: String) -> Bool {
        switch action {
        case "copy":
            copySelection(cut: false)
            return true
        case "cut":
            copySelection(cut: true)
            return true
        case "find":
            return openSearch()
        case "selectAll":
            callEditorCommand("window.SuixinjiEditor && window.SuixinjiEditor.selectAll();")
            return true
        case "undo":
            callEditorCommand("window.SuixinjiEditor && window.SuixinjiEditor.undo();")
            return true
        case "redo":
            callEditorCommand("window.SuixinjiEditor && window.SuixinjiEditor.redo();")
            return true
        default:
            return false
        }
    }

    private func callEditorCommand(_ javascript: String) {
        guard pageReady else { return }
        evaluate(javascript)
    }

    private func copySelection(cut: Bool) {
        guard pageReady else { return }
        webView.callAsyncJavaScript(
            """
            (() => {
              const selection = window.getSelection();
              if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null;
              const range = selection.getRangeAt(0);
              const container = document.createElement('div');
              container.appendChild(range.cloneContents());
              return JSON.stringify({ text: selection.toString(), html: container.innerHTML });
            })()
            """,
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard case .success(let value) = result,
                  let json = value as? String,
                  let data = json.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                // Keep WebKit's native command as a fallback if the
                // structured selection cannot be bridged. The previous code
                // only copied here; Cmd+X therefore became a no-op whenever
                // the bridge failed.
                if cut {
                    self?.evaluate("document.execCommand('cut');")
                } else {
                    self?.evaluate("document.execCommand('copy');")
                }
                return
            }
            let text = payload["text"] as? String ?? ""
            let html = payload["html"] as? String ?? ""
            guard !text.isEmpty || !html.isEmpty else {
                if cut { self?.evaluate("document.execCommand('cut');") }
                return
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if !text.isEmpty {
                pasteboard.setString(text, forType: .string)
            }
            if !html.isEmpty {
                pasteboard.setString(html,
                                    forType: NSPasteboard.PasteboardType("public.html"))
            }
            if cut {
                self?.callEditorCommand("window.SuixinjiEditor && window.SuixinjiEditor.deleteSelection();")
            }
        }
    }

    func handleEscape() -> Bool {
        if let controller = imagePreviewController,
           controller.window?.isVisible == true {
            controller.close()
            imagePreviewController = nil
            evaluate("window.SuixinjiEditor && window.SuixinjiEditor.closePreview();")
            return true
        }
        guard searchVisible else { return false }
        searchVisible = false
        callEditorCommand("window.SuixinjiEditor && window.SuixinjiEditor.closeSearch();")
        return true
    }

    private func showImagePreview(source: String) {
        guard let image = imageFromSource(source) else {
            NSLog("[suixinji] native image preview could not decode source")
            return
        }
        imagePreviewController?.close()
        let controller = ImagePreviewWindowController(image: image,
                                                       screen: view.window?.screen)
        imagePreviewController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func imageFromSource(_ source: String) -> NSImage? {
        if let comma = source.firstIndex(of: ","),
           source[..<comma].lowercased().contains("base64") {
            let encoded = String(source[source.index(after: comma)...])
            if let data = Data(base64Encoded: encoded) {
                return NSImage(data: data)
            }
        }
        if let url = URL(string: source), url.isFileURL,
           let data = try? Data(contentsOf: url) {
            return NSImage(data: data)
        }
        return nil
    }

    // MARK: - Bridge

    private func payloadForExistingNote(_ id: String) -> [String: Any] {
        if let data = store.loadWebDocumentData(id),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let normalized = normalizedWebPayload(object, noteId: id)
            if let normalizedData = try? JSONSerialization.data(withJSONObject: normalized) {
                // Persist the migration so the same legacy file reference is
                // not reintroduced on the next launch.
                store.rewriteWebDocumentData(id, document: normalizedData)
            }
            return normalized
        }
        if let html = store.legacyHTMLForWebEditor(id) {
            return ["version": 1, "html": html]
        }
        return ["version": 1,
                "content": ["type": "doc", "content": [["type": "paragraph"]]]]
    }

    /// Older native HTML conversion produced `file:///Attachment.png` image
    /// attrs. Convert those references to data URLs before they enter the
    /// browser so existing notes display even when their path is relative to
    /// an RTFD package.
    private func normalizedWebPayload(_ payload: [String: Any], noteId: String) -> [String: Any] {
        normalizeWebValue(payload, noteId: noteId) as? [String: Any] ?? payload
    }

    private func normalizeWebValue(_ value: Any, noteId: String) -> Any {
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, child) in dict {
                if key == "src", let src = child as? String,
                   let dataURL = store.dataURLForLegacyImage(src, noteId: noteId) {
                    result[key] = dataURL
                } else {
                    result[key] = normalizeWebValue(child, noteId: noteId)
                }
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { normalizeWebValue($0, noteId: noteId) }
        }
        return value
    }

    private func sendPendingPayloadIfReady() {
        guard pageReady else { return }
        guard let payload = pendingPayload else {
            if let paste = pendingPaste {
                pendingPaste = nil
                _ = insertPendingPaste(paste)
            }
            return
        }
        pendingPayload = nil
        let queuedPaste = pendingPaste
        pendingPaste = nil
        // Pass the document as a structured WebKit argument. A note with a
        // pasted image may contain megabytes of base64 and must not be copied
        // into a JavaScript source string.
        webView.callAsyncJavaScript(
            "window.SuixinjiEditor && window.SuixinjiEditor.loadDocument(payload)",
            arguments: ["payload": payload],
            in: nil,
            in: .page
        ) { result in
            if case .failure(let error) = result {
                NSLog("[suixinji] document load bridge error: \(error)")
            }
            // Loading a note replaces the document, so a paste queued during
            // page startup must happen only after that replacement completes.
            if let queuedPaste {
                _ = self.insertPendingPaste(queuedPaste)
            }
        }
    }

    private func evaluate(_ javascript: String) {
        webView.evaluateJavaScript(javascript) { _, error in
            if let error {
                NSLog("[suixinji] web editor bridge error: \(error)")
            }
        }
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            self?.flush(userInitiated: false)
        }
    }

    private func receiveChange(_ payload: [String: Any]) {
        guard let id = currentNoteId,
              let document = payload["document"] as? [String: Any],
              JSONSerialization.isValidJSONObject(document),
              let data = try? JSONSerialization.data(withJSONObject: document) else { return }
        latestDocument = data
        latestHTML = payload["html"] as? String
        if let title = payload["title"] as? String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            latestTitle = trimmed.isEmpty ? "无标题" : trimmed
        } else {
            latestTitle = "无标题"
        }
        dirty = true
        delegate?.editorSaveStatus("未保存")
        scheduleSave()
        _ = id
    }

    private func receiveMessage(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        switch type {
        case "ready":
            pageReady = true
            sendPendingPayloadIfReady()
            NSLog("[suixinji] web editor ready")
        case "change":
            receiveChange(payload)
        case "outline":
            guard let rawItems = payload["items"] as? [Any] else {
                delegate?.editorOutlineDidChange([])
                break
            }
            let items = rawItems.compactMap { rawItem -> EditorOutlineItem? in
                guard let item = rawItem as? [String: Any],
                      let title = item["title"] as? String,
                      let index = (item["index"] as? NSNumber)?.intValue,
                      let level = (item["level"] as? NSNumber)?.intValue else { return nil }
                return EditorOutlineItem(title: title,
                                         level: max(1, min(5, level)),
                                         index: index)
            }
            delegate?.editorOutlineDidChange(items)
        case "outlineSelection":
            let index = (payload["index"] as? NSNumber)?.intValue
                ?? (payload["index"] as? Int)
            delegate?.editorOutlineSelectionDidChange(index)
        case "searchClosed":
            searchVisible = false
        case "imagePreview":
            if payload["visible"] as? Bool == true,
               let source = payload["src"] as? String {
                showImagePreview(source: source)
            }
        case "rendered":
            let count = payload["imageCount"] as? Int ?? 0
            NSLog("[suixinji] web editor rendered images=\(count) note=\(currentNoteId ?? "nil")")
        case "imageInserted":
            NSLog("[suixinji] web editor image inserted=\(payload["ok"] as? Bool ?? false)")
        case "imageError":
            NSLog("[suixinji] web editor image failed to load")
        default:
            break
        }
    }
}

extension WKWebViewEditorViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "suixinji",
              let payload = message.body as? [String: Any] else { return }
        receiveMessage(payload)
    }
}

extension WKWebViewEditorViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        NSLog("[suixinji] web editor navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        NSLog("[suixinji] web editor provisional navigation failed: \(error)")
    }
}
