import Foundation
import AppKit

/// Reads/writes notes and categories on disk.
///
/// Storage formats:
/// - the original `.rtfd` package plus `<id>.meta.json` sidecar;
/// - an optional `<id>.web.json` ProseMirror document written by the
///   experimental WKWebView editor.
///
/// The web document is deliberately side-by-side with RTFD. Enabling the web
/// editor never destroys the native editor's data, so switching engines is a
/// reversible choice.
///
/// Legacy `.html` notes (from the Tauri version) are read on a best-effort
/// basis; the first save rewrites them as `.rtfd` and removes the old html.
final class NotesStore {

    static let notesIconKey = "note-icon"
    static let notesCategoryKey = "note-category"

    let notesDir: URL
    private let fm = FileManager.default

    init() {
        self.notesDir = NotesStore.resolveNotesDir()
    }

    static func resolveNotesDir() -> URL {
        let fm = FileManager.default

        // 1. Explicit env override (highest priority, mirrors Tauri).
        if let env = ProcessInfo.processInfo.environment["SUIXINJI_NOTES_DIR"], !env.isEmpty {
            let url = URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        // 2. Dev: walk up from the running executable looking for the repo root,
        //    so Swift dev reads/writes the same `notes/.notes` as Tauri dev.
        if let dev = findDevNotesDir(in: fm) {
            try? fm.createDirectory(at: dev, withIntermediateDirectories: true)
            return dev
        }

        // 3. Installed: stable, guaranteed-writable per-user location.
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let candidate = support.appendingPathComponent("com.suixinji.app/.notes", isDirectory: true)
        try? fm.createDirectory(at: candidate, withIntermediateDirectories: true)
        return candidate
    }

    /// Walk up from the running executable's directory looking for the repo root
    /// — a directory containing `src-tauri` plus `package.json` or `.notes` — and
    /// return its `.notes` subdir. Mirrors Tauri's `notes_dir` dev probe so the
    /// two builds share `notes/.notes` during development. Returns nil in a
    /// packaged install (no repo markers up the tree), forcing the caller to
    /// fall back to the per-user Application Support path.
    private static func findDevNotesDir(in fm: FileManager) -> URL? {
        // A packaged application has no reason to search upwards from
        // /Applications/随心记.app. On macOS 26, repeatedly asking Foundation
        // to append paths while walking a bundle URL can get stuck in URL/file
        // provider resolution before the first window is created. Packaged
        // builds always use the per-user Application Support directory instead.
        guard Bundle.main.bundleURL.pathExtension.lowercased() != "app" else {
            return nil
        }

        // Candidate start directories: the main bundle URL (a `.app` directory
        // in a packaged install, the bare executable file for a `swift run` CLI
        // build) and the invoked executable path from CommandLine.arguments.
        var startDirs: [URL] = []
        let bundleURL = Bundle.main.bundleURL
        startDirs.append(bundleURL.hasDirectoryPath ? bundleURL : bundleURL.deletingLastPathComponent())
        if let arg0 = CommandLine.arguments.first {
            startDirs.append(URL(fileURLWithPath: arg0).deletingLastPathComponent())
        }

        var visited = Set<String>()
        for var dir in startDirs {
            var depth = 0
            while true {
                let normalizedPath = dir.standardizedFileURL.path
                guard visited.insert(normalizedPath).inserted, depth < 32 else { break }
                depth += 1

                let hasSrcTauri = fm.fileExists(atPath: dir.appendingPathComponent("src-tauri").path)
                let hasPkg = fm.fileExists(atPath: dir.appendingPathComponent("package.json").path)
                let hasNotes = fm.fileExists(atPath: dir.appendingPathComponent(".notes").path)
                if hasSrcTauri && (hasPkg || hasNotes) {
                    return dir.appendingPathComponent(".notes", isDirectory: true)
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break } // reached filesystem root
                dir = parent
            }
        }
        return nil
    }

    // MARK: - Categories

    private var categoriesURL: URL { notesDir.appendingPathComponent("categories.json") }

    func listCategories() -> [Category] {
        guard let data = try? Data(contentsOf: categoriesURL) else { return [] }
        return (try? JSONDecoder().decode([Category].self, from: data)) ?? []
    }

    func saveCategories(_ cats: [Category]) {
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        let data = (try? JSONEncoder().encode(cats)) ?? Data("[]".utf8)
        try? data.write(to: categoriesURL, options: .atomic)
    }

    /// Create (id empty) or rename a category. Returns the id.
    @discardableResult
    func upsertCategory(id: String, name: String) -> String {
        var cats = listCategories()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return id }
        if id.isEmpty {
            let newId = newNoteId()
            cats.append(Category(id: newId, name: trimmed))
            saveCategories(cats)
            return newId
        } else {
            if let idx = cats.firstIndex(where: { $0.id == id }) {
                cats[idx].name = trimmed
            } else {
                cats.append(Category(id: id, name: trimmed))
            }
            saveCategories(cats)
            return id
        }
    }

    func deleteCategory(id: String) {
        var cats = listCategories()
        cats.removeAll { $0.id == id }
        saveCategories(cats)
        // Clear the category on every note that referenced it.
        for meta in listNotes() where meta.category == id {
            var m = meta
            m.category = ""
            writeMeta(m)
        }
    }

    func setNoteCategory(noteId: String, categoryId: String) {
        guard var m = metaForId(noteId) else { return }
        m.category = categoryId
        writeMeta(m)
    }

    // MARK: - Listing

    /// All note ids present on disk (rtfd packages and legacy html).
    private func allNoteIds() -> [String] {
        guard let entries = try? fm.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil) else { return [] }
        var ids = Set<String>()
        for url in entries {
            let name = url.lastPathComponent
            if name.hasSuffix(".rtfd") {
                ids.insert(String(name.dropLast(5)))
            } else if name.hasSuffix(".web.json") {
                ids.insert(String(name.dropLast(".web.json".count)))
            } else if name.hasSuffix(".meta.json") {
                ids.insert(String(name.dropLast(".meta.json".count)))
            } else if name.hasSuffix(".html") {
                ids.insert(String(name.dropLast(5)))
            }
        }
        return Array(ids)
    }

    func listNotes() -> [NoteMeta] {
        var metas: [NoteMeta] = []
        for id in allNoteIds() {
            if let m = metaForId(id) { metas.append(m) }
        }
        // File timestamps are stored at second precision for compatibility
        // with the Tauri metadata. Tie-break by id so refreshes never shuffle
        // notes that were saved during the same second.
        metas.sort {
            if $0.mtime != $1.mtime { return $0.mtime > $1.mtime }
            return $0.id > $1.id
        }
        return metas
    }

    // MARK: - Meta read/write

    private func rtfdURL(_ id: String) -> URL { notesDir.appendingPathComponent("\(id).rtfd") }
    private func htmlURL(_ id: String) -> URL { notesDir.appendingPathComponent("\(id).html") }
    private func metaURL(_ id: String) -> URL { notesDir.appendingPathComponent("\(id).meta.json") }

    private func metaForId(_ id: String) -> NoteMeta? {
        // Prefer sidecar meta.json.
        if let data = try? Data(contentsOf: metaURL(id)),
           var m = try? JSONDecoder().decode(NoteMeta.self, from: data) {
            // Titles are always derived from the first non-empty line, not
            // from heading level. Recompute existing sidecars so notes saved
            // with the old H1-first rule are corrected on the next refresh.
            let derived: String
            if hasWebDocument(id) {
                derived = deriveTitle(fromWebDocument: id)
            } else if let attr = loadAttributedString(id), attr.length > 0 {
                derived = deriveTitle(from: attr)
            } else {
                derived = "无标题"
            }
            if m.title != derived {
                m.title = derived
                writeMeta(m)
            }
            return m
        }
        // Fall back to legacy html header parsing.
        if let html = try? String(contentsOf: htmlURL(id), encoding: .utf8) {
            return parseLegacyHTML(id: id, html: html)
        }
        // Derive from rtfd content.
        if fm.fileExists(atPath: rtfdURL(id).path) {
            let attr = loadAttributedString(id) ?? NSAttributedString()
            let attrs = try? fm.attributesOfItem(atPath: rtfdURL(id).path)
            let mod = (attrs?[.modificationDate] as? Date) ?? Date()
            return NoteMeta(id: id,
                            title: deriveTitle(from: attr),
                            icon: "📝",
                            category: "",
                            mtime: Int(mod.timeIntervalSince1970))
        }
        return nil
    }

    private func writeMeta(_ meta: NoteMeta) {
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaURL(meta.id), options: .atomic)
        }
    }

    // MARK: - Load / save content

    private func webDocumentURL(_ id: String) -> URL {
        notesDir.appendingPathComponent("\(id).web.json")
    }

    /// Returns the raw ProseMirror JSON for the WKWebView editor, if present.
    /// The native RTFD document is intentionally not used here: both formats
    /// can coexist while the editor engine is being evaluated.
    func loadWebDocumentData(_ id: String) -> Data? {
        try? Data(contentsOf: webDocumentURL(id))
    }

    func rewriteWebDocumentData(_ id: String, document: Data) {
        guard (try? JSONSerialization.jsonObject(with: document)) != nil else { return }
        try? document.write(to: webDocumentURL(id), options: .atomic)
    }

    func hasWebDocument(_ id: String) -> Bool {
        fm.fileExists(atPath: webDocumentURL(id).path)
    }

    /// Convert an existing native/legacy note into initial HTML for the web
    /// editor. This is read-only conversion; the original RTFD/HTML remains.
    func legacyHTMLForWebEditor(_ id: String) -> String? {
        guard let attr = loadAttributedString(id), attr.length > 0 else {
            return nil
        }
        let options: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let data = try? attr.data(from: NSRange(location: 0, length: attr.length),
                                     documentAttributes: options),
           let html = String(data: data, encoding: .utf8) {
            return embedLegacyImageReferences(in: html, noteId: id)
        }
        return "<p>\(htmlEscaped(attr.string))</p>"
    }

    /// Resolve an image reference emitted by the old HTML/RTFD converter and
    /// return a browser-safe data URL. RTFD attachments are stored beside the
    /// note, while the converter commonly emits only `file:///Attachment.png`.
    func dataURLForLegacyImage(_ source: String, noteId: String) -> String? {
        guard !source.isEmpty, !source.hasPrefix("data:") else { return nil }

        let decoded = source.removingPercentEncoding ?? source
        var candidates: [URL] = []
        if let url = URL(string: decoded), url.isFileURL {
            candidates.append(url)
        }
        let relative = URL(fileURLWithPath: decoded).path
        candidates.append(notesDir.appendingPathComponent(relative))
        let filename = URL(fileURLWithPath: relative).lastPathComponent
        if !filename.isEmpty {
            candidates.append(rtfdURL(noteId).appendingPathComponent(filename))
        }

        guard let fileURL = candidates.first(where: { fm.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        let ext = fileURL.pathExtension.lowercased()
        let mime: String
        switch ext {
        case "jpg", "jpeg": mime = "image/jpeg"
        case "gif": mime = "image/gif"
        case "webp": mime = "image/webp"
        case "tif", "tiff": mime = "image/tiff"
        default: mime = "image/png"
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private func embedLegacyImageReferences(in html: String, noteId: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(<img\b[^>]*\bsrc\s*=\s*[\"'])([^\"']+)([\"'])"#,
            options: [.caseInsensitive]) else { return html }
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: fullRange)
        let mutable = NSMutableString(string: html)
        for match in matches.reversed() {
            guard match.numberOfRanges > 2,
                  let sourceRange = Range(match.range(at: 2), in: html) else { continue }
            let source = String(html[sourceRange])
            guard let dataURL = dataURLForLegacyImage(source, noteId: noteId) else { continue }
            mutable.replaceCharacters(in: match.range(at: 2), with: dataURL)
        }
        return mutable as String
    }

    /// Persist a web-editor document and keep a best-effort native fallback.
    func saveWebNote(id: String, document: Data, meta: NoteMeta, html: String? = nil) {
        guard (try? JSONSerialization.jsonObject(with: document)) != nil else {
            NSLog("[suixinji] refused invalid web document for \(id)")
            return
        }
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        // Keep the rollback path useful: update the native representation when
        // AppKit can import the editor's HTML. ProseMirror JSON remains the
        // source of truth for the Web editor, so an HTML import limitation does
        // not prevent the JSON save below.
        var updatedMeta = meta
        updatedMeta.mtime = Int(Date().timeIntervalSince1970)
        // AppKit's HTML importer is not a safe bridge for arbitrary web
        // images: importing a large base64 data URL can fail or crash while
        // the WebKit editor is autosaving. The .web.json document is the
        // source of truth for this engine, so keep the old RTFD untouched for
        // image-bearing documents and only refresh the text fallback when the
        // HTML contains no image element.
        if let html,
           html.range(of: #"<img\b"#, options: [.regularExpression, .caseInsensitive]) == nil,
           let htmlData = html.data(using: .utf8),
           let attr = try? NSAttributedString(
               data: htmlData,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue
               ],
               documentAttributes: nil),
           attr.length > 0 {
            saveNote(id: id, content: attr, meta: updatedMeta)
        }
        do {
            try document.write(to: webDocumentURL(id), options: .atomic)
        } catch {
            NSLog("[suixinji] failed to write web document for \(id): \(error)")
            return
        }
        updatedMeta.mtime = Int(Date().timeIntervalSince1970)
        writeMeta(updatedMeta)
    }

    func loadAttributedString(_ id: String) -> NSAttributedString? {
        let rtfd = rtfdURL(id)
        if fm.fileExists(atPath: rtfd.path) {
            let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.rtfd
            ]
            if let attr = try? NSAttributedString(url: rtfd, options: opts, documentAttributes: nil) {
                return attr
            }
        }
        if let html = try? String(contentsOf: htmlURL(id), encoding: .utf8) {
            return parseLegacyHTMLBody(html: html, noteId: id)
        }
        return nil
    }

    /// Save the note content as an RTFD package and refresh its meta sidecar.
    func saveNote(id: String, content: NSAttributedString, meta: NoteMeta) {
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        // A native save is an explicit engine switch back to NSTextView. Let
        // the Web editor rebuild its JSON from this newer RTFD next time.
        try? fm.removeItem(at: webDocumentURL(id))
        let storage = content is NSTextStorage ? (content as! NSTextStorage) : NSTextStorage(attributedString: content)
        do {
            let wrapper = try storage.fileWrapper(
                from: NSRange(location: 0, length: content.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
            // Remove old package contents first so stale images don't linger.
            if fm.fileExists(atPath: rtfdURL(id).path) {
                try? fm.removeItem(at: rtfdURL(id))
            }
            try wrapper.write(to: rtfdURL(id), options: .atomic, originalContentsURL: nil)
        } catch {
            NSLog("[suixinji] failed to write rtfd for \(id): \(error)")
        }
        // Drop legacy html now that rtfd exists.
        if fm.fileExists(atPath: htmlURL(id).path) {
            try? fm.removeItem(at: htmlURL(id))
        }
        var m = meta
        m.mtime = Int(Date().timeIntervalSince1970)
        writeMeta(m)
    }

    func deleteNote(id: String) {
        try? fm.removeItem(at: rtfdURL(id))
        try? fm.removeItem(at: webDocumentURL(id))
        try? fm.removeItem(at: metaURL(id))
        try? fm.removeItem(at: htmlURL(id))
    }

    private func htmlEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Legacy HTML parsing

    private func parseLegacyHTML(id: String, html: String) -> NoteMeta {
        let title = match(pattern: #"<title[^>]*>(.*?)</title>"#, in: html) ?? "无标题"
        let icon = match(pattern: #"<meta\s+name="note-icon"\s+content="([^"]*)""#, in: html) ?? "📝"
        let category = match(pattern: #"<meta\s+name="note-category"\s+content="([^"]*)""#, in: html) ?? ""
        // mtime from file mtime.
        let attrs = try? fm.attributesOfItem(atPath: htmlURL(id).path)
        let mod = (attrs?[.modificationDate] as? Date) ?? Date()
        return NoteMeta(id: id, title: title, icon: icon, category: category, mtime: Int(mod.timeIntervalSince1970))
    }

    private func parseLegacyHTMLBody(html: String, noteId: String) -> NSAttributedString {
        // Extract <body>...</body>
        let body: String
        if let bodyRange = html.range(of: #"<body[^>]*>(.*?)</body>"#, options: .regularExpression) {
            body = String(html[bodyRange]).replacingOccurrences(of: #"<body[^>]*>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "</body>", with: "")
        } else {
            body = html
        }

        // The HTML→NSAttributedString converter cannot load Tauri's local
        // `assets/<id>/<file>` img refs, so images would be lost. To keep both
        // the image bytes and their in-text position, scan `<img>` tags in
        // order, swap each for a numbered ASCII placeholder, run the HTML
        // conversion, then splice NSTextAttachment runs back into the
        // placeholder spots.
        let (placeholderBody, relPaths) = replaceLegacyImgTagsWithPlaceholders(body)
        let data = placeholderBody.data(using: .utf8) ?? Data()
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        let parsed: NSAttributedString
        if let attr = try? NSAttributedString(data: data, options: opts, documentAttributes: nil) {
            parsed = attr
        } else {
            parsed = NSAttributedString(string: placeholderBody)
        }
        return injectImageAttachments(into: parsed, relPaths: relPaths, noteId: noteId)
    }

    /// Scan every `<img ...>` in `body`, capture its relative image path
    /// (`data-note-src` preferred, else a local `src`), and replace the tag
    /// with a numbered plaintext placeholder `__IMG<n>__` so the image
    /// position survives HTML→NSAttributedString conversion. Tags with no
    /// usable local ref (e.g. remote/blob/data URLs) are dropped. Returns the
    /// rewritten body and the ordered list of captured relative paths.
    private func replaceLegacyImgTagsWithPlaceholders(_ body: String) -> (String, [String]) {
        guard let regex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#,
                                                   options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return (body, [])
        }
        var relPaths: [String] = []
        var rewritten = ""
        let nsBody = body as NSString
        var cursor = 0
        let fullRange = NSRange(location: 0, length: nsBody.length)
        regex.enumerateMatches(in: body, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let tagRange = match.range
            if tagRange.location > cursor {
                rewritten += nsBody.substring(with: NSRange(location: cursor,
                                                            length: tagRange.location - cursor))
            }
            let tag = nsBody.substring(with: tagRange)
            if let rel = legacyImageRelPath(in: tag) {
                let idx = relPaths.count
                relPaths.append(rel)
                rewritten += "__IMG\(idx)__"
            }
            cursor = tagRange.location + tagRange.length
        }
        if cursor < nsBody.length {
            rewritten += nsBody.substring(from: cursor)
        }
        return (rewritten, relPaths)
    }

    /// Pull the relative image path out of an `<img ...>` tag: prefer
    /// `data-note-src` (Tauri's canonical ref), fall back to `src` only when it
    /// is a local relative ref — i.e. not an absolute URL scheme, `blob:`, or
    /// `data:` URL. Returns nil for remote-only imgs (nothing to embed).
    private func legacyImageRelPath(in tag: String) -> String? {
        if let v = match(pattern: #"\bdata-note-src\s*=\s*\"([^\"]*)\""#, in: tag), !v.isEmpty {
            return v
        }
        guard let v = match(pattern: #"\bsrc\s*=\s*\"([^\"]*)\""#, in: tag), !v.isEmpty else {
            return nil
        }
        if v.contains("://") || v.hasPrefix("blob:") || v.hasPrefix("data:") {
            return nil
        }
        return v
    }

    /// Replace each `__IMG<n>__` placeholder in `parsed` with an inline image
    /// NSTextAttachment built from the referenced local file. Relative paths
    /// (e.g. `assets/<noteId>/<file>`) resolve against the note's html
    /// directory, which is the same dir Tauri wrote them into. Missing files
    /// are silently dropped (placeholder removed) so a lost asset never breaks
    /// note loading.
    private func injectImageAttachments(into parsed: NSAttributedString,
                                        relPaths: [String],
                                        noteId: String) -> NSAttributedString {
        if relPaths.isEmpty { return parsed }
        let baseDir = htmlURL(noteId).deletingLastPathComponent()
        let mutable = NSMutableAttributedString(attributedString: parsed)
        for (idx, rel) in relPaths.enumerated() {
            let token = "__IMG\(idx)__"
            let absURL = URL(fileURLWithPath: rel, relativeTo: baseDir)
            guard let data = try? Data(contentsOf: absURL),
                  let attachment = makeImageAttachment(data: data, relPath: rel) else {
                continue
            }
            let imgAttr = NSAttributedString(attachment: attachment)
            while let tokenRange = mutable.string.range(of: token) {
                let nsRange = NSRange(tokenRange, in: mutable.string)
                mutable.replaceCharacters(in: nsRange, with: imgAttr)
            }
        }
        return mutable
    }

    /// Build an inline image NSTextAttachment from raw image bytes. `relPath`
    /// supplies the extension (for the UTI + preferred filename). Bounds are
    /// derived from the decoded NSImage. The editor applies the final
    /// available-column constraint after the note is loaded.
    private func makeImageAttachment(data: Data, relPath: String) -> NSTextAttachment? {
        let ext = (relPath as NSString).pathExtension.lowercased()
        let baseName = ((relPath as NSString).lastPathComponent as NSString).deletingPathExtension
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = baseName.isEmpty ? "image.\(ext)" : "\(baseName).\(ext)"
        let attachment = NSTextAttachment()
        attachment.fileType = uti(for: ext)
        attachment.fileWrapper = wrapper
        if let image = NSImage(data: data) {
            let size = image.size
            // Keep the decoded image as the explicit drawing source. The file
            // wrapper is still used for RTFD persistence, but relying on
            // AppKit to decode the attachment lazily can crash while drawing
            // attachments imported from external images on macOS 26.
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: 0,
                                       width: size.width,
                                       height: size.height)
        }
        return attachment
    }

    /// Map a file extension to the UTI used for inline image attachment
    /// rendering. Mirrors EditorTextView.uti(for:) so legacy imgs embed with
    /// the same type without NotesStore depending on the editor class.
    private func uti(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "public.jpeg"
        case "gif": return "com.compuserve.gif"
        case "bmp": return "com.microsoft.bmp"
        case "webp": return "org.webmproject.webp"
        case "svg": return "public.svg-image"
        default: return "public.png"
        }
    }

    private func match(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = regex.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    // MARK: - Title derivation

    /// First non-empty line of the note (truncated to 80 chars).
    func deriveTitle(from attr: NSAttributedString) -> String {
        for line in attr.string.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { return String(s.prefix(80)) }
        }
        return "无标题"
    }

    private func deriveTitle(fromWebDocument id: String) -> String {
        guard let data = loadWebDocumentData(id),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "无标题"
        }
        let root: Any = object["content"] as? [String: Any] ?? object
        let text = webText(from: root)
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let value = line.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return String(value.prefix(80)) }
        }
        return "无标题"
    }

    private func webText(from value: Any) -> String {
        if let text = value as? String { return text }
        if let dict = value as? [String: Any] {
            if dict["type"] as? String == "text" {
                return dict["text"] as? String ?? ""
            }
            let type = dict["type"] as? String ?? ""
            let children = (dict["content"] as? [Any] ?? []).map(webText)
            let separator: String
            switch type {
            case "doc", "blockquote", "bulletList", "orderedList", "listItem", "table", "tableRow":
                separator = "\n"
            case "tableCell", "tableHeader":
                separator = " "
            default:
                separator = ""
            }
            return children.joined(separator: separator)
        }
        if let array = value as? [Any] {
            return array.map(webText).joined(separator: "\n")
        }
        return ""
    }
}
