import AppKit

/// Dark theme tokens for 随心记 native UI.
///
/// Colors mirror `src/styles/theme.css` (`:root`) exactly so the native UI stays
/// in lock-step with the legacy Tauri design:
///   bg #1d1d1f, panel #242427, rail #1a1a1c, elevated #2f2f33, border #38383c,
///   text #ececee, text-dim #9a9a9e, accent #0a84ff, accent-soft rgba(10,132,255,.18),
///   danger #ff453a.
enum Theme {
    static let bg          = NSColor(srgbRed: 0x1d/255.0, green: 0x1d/255.0, blue: 0x1f/255.0, alpha: 1.0)
    static let panel       = NSColor(srgbRed: 0x24/255.0, green: 0x24/255.0, blue: 0x27/255.0, alpha: 1.0)
    static let rail        = NSColor(srgbRed: 0x1a/255.0, green: 0x1a/255.0, blue: 0x1c/255.0, alpha: 1.0)
    static let elevated    = NSColor(srgbRed: 0x2f/255.0, green: 0x2f/255.0, blue: 0x33/255.0, alpha: 1.0)
    static let border      = NSColor(srgbRed: 0x38/255.0, green: 0x38/255.0, blue: 0x3c/255.0, alpha: 1.0)
    static let text        = NSColor(srgbRed: 0xec/255.0, green: 0xec/255.0, blue: 0xee/255.0, alpha: 1.0)
    static let textDim     = NSColor(srgbRed: 0x9a/255.0, green: 0x9a/255.0, blue: 0x9e/255.0, alpha: 1.0)
    static let accent      = NSColor(srgbRed: 0x0a/255.0, green: 0x84/255.0, blue: 0xff/255.0, alpha: 1.0)
    static let accentHover = NSColor(srgbRed: 0x40/255.0, green: 0x9c/255.0, blue: 0xff/255.0, alpha: 1.0)
    static let accentSoft  = NSColor(srgbRed: 0x0a/255.0, green: 0x84/255.0, blue: 0xff/255.0, alpha: 0.18)
    static let danger      = NSColor(srgbRed: 0xff/255.0, green: 0x45/255.0, blue: 0x3a/255.0, alpha: 1.0)
    static let dangerSoft  = NSColor(srgbRed: 0xff/255.0, green: 0x45/255.0, blue: 0x3a/255.0, alpha: 0.12)

    // Backward-compatible aliases mapping the old native names onto the CSS
    // tokens they now represent.
    static let background       = bg
    static let sidebar          = panel        // split-list / topbar / toolbar surface = var(--panel)
    static let card             = elevated
    static let cardHover        = elevated
    static let separator        = border
    static let secondaryText    = textDim
    static let editorBackground = bg           // .split-editor background = var(--bg)
    static let codeBackground   = elevated     // inline `code` background = var(--elevated)
    static let codeKeyword      = NSColor(srgbRed: 0.98, green: 0.45, blue: 0.62, alpha: 1)
    static let codeString       = NSColor(srgbRed: 0.45, green: 0.82, blue: 0.55, alpha: 1)
    static let codeNumber       = NSColor(srgbRed: 0.55, green: 0.72, blue: 1.00, alpha: 1)
    static let codeComment      = NSColor(srgbRed: 0.52, green: 0.58, blue: 0.64, alpha: 1)
    static let quoteColor       = textDim      // blockquote color = var(--text-dim)

    // Fonts (App.css: topbar 13/600, body 15, section 11/600, card title 13/600).
    static let titleFont     = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let bodyFont      = NSFont.systemFont(ofSize: 15)
    static let editorLineHeightMultiple = CGFloat(1.3)
    static let smallFont     = NSFont.systemFont(ofSize: 11)
    static let smallBoldFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let cardTitleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let monoFont      = NSFont(name: "SFMono-Regular", size: 13.5)
        ?? NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)

    // Corner radii (App.css).
    static let cornerRadius       = CGFloat(8)
    static let cardCornerRadius   = CGFloat(12)
    static let buttonCornerRadius = CGFloat(6)
}

extension NSView {
    /// Apply a rounded dark card background (note-card surface).
    func applyCardStyle() {
        wantsLayer = true
        layer?.backgroundColor = Theme.card.cgColor
        layer?.cornerRadius = Theme.cardCornerRadius
    }
}
