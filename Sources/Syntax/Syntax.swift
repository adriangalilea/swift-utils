import Highlightr
import SwiftUI
@_exported import SyntaxLines

/// Review-body coloring for approval surfaces: the text a human reads before
/// saying yes, told apart by what the requester SAID it is, never guessed.
/// Code goes through real grammars (highlight.js via Highlightr) - a shell
/// line, a heredoc's embedded python, a script - with automatic language
/// detection where the declared format doesn't pin one. A diff stays
/// hand-colored by line prefix: red/green with `@@` headers muted, because
/// our diff format is ours and its semantics are exact. Coloring never
/// rewrites a character: the output's characters are the input, exactly,
/// so what is approved is what was shown.
public enum Syntax {
    /// The highlight.js theme the colors come from. Foreground colors only -
    /// the host owns background and font - so pick one whose inks read on
    /// your surfaces. Every current surface is dark glass.
    public static var theme: String {
        get { store.lock.withLock { store.theme } }
        set {
            store.lock.withLock {
                store.theme = newValue
                store.cache = [:]
                store.order = []
            }
        }
    }

    /// Above this the grammar pass is skipped outright: JSC on hundreds of
    /// kilobytes stalls the render for something nobody reads colored.
    public static let ceiling = 32 * 1024

    public static func highlight(_ text: String, as format: CodeFormat) -> AttributedString {
        switch format {
        case .diff: return SyntaxLines.diff(text)
        case .plain: return AttributedString(text)
        case .shell:
            guard text.utf8.count <= ceiling else { return AttributedString(text) }
            let key = "\(theme)|\(format.rawValue)|\(text.hashValue)"
            if let hit = cached(key) { return hit }
            // A multi-line "shell" body is usually a script riding a heredoc
            // or a -c string; detection reads the content, the bash grammar
            // would paint it all as one string. A single line IS shell.
            let colored =
                code(text, language: text.contains("\n") ? nil : "bash")
                ?? AttributedString(text)
            remember(key, colored)
            return colored
        }
    }

    /// The grammar's inks for `text` as data (`CodeColors`), for a surface
    /// that cannot run the engine to paint (`CodeExcerpt(colors:)`). Nil for
    /// a diff (line-colored without an engine) and plain text, or when the
    /// grammar gives nothing.
    public static func colors(_ text: String, as format: CodeFormat) -> CodeColors? {
        guard format == .shell, text.utf8.count <= ceiling else { return nil }
        let colored = highlight(text, as: format)
        var palette: [String] = []
        var runs: [[Int]] = []
        for run in colored.runs {
            let count = colored[run.range].characters.count
            var ink = -1
            if let color = run.foregroundColor, let hex = hex(color) {
                if let at = palette.firstIndex(of: hex) {
                    ink = at
                } else {
                    palette.append(hex)
                    ink = palette.count - 1
                }
            }
            if let last = runs.last, last[1] == ink {
                runs[runs.count - 1][0] += count
            } else {
                runs.append([count, ink])
            }
        }
        return palette.isEmpty ? nil : CodeColors(palette: palette, runs: runs)
    }

    private static func hex(_ color: Color) -> String? {
        #if canImport(AppKit)
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
            let (r, g, b) = (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        #else
            var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #endif
        let byte = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b))
    }

    // MARK: - the engine

    /// One highlight.js instance (a JSContext loading ~1MB of grammar is not
    /// a per-render cost), everything mutable behind one lock: Highlightr is
    /// not thread-safe and Swift 6 wants the claim explicit.
    private static let store = Store()
    private final class Store: @unchecked Sendable {
        let lock = NSLock()
        let engine = Highlightr()
        var theme = "atom-one-dark"
        var cache: [String: AttributedString] = [:]
        var order: [String] = []
    }

    private static func cached(_ key: String) -> AttributedString? {
        store.lock.withLock { store.cache[key] }
    }

    private static func remember(_ key: String, _ value: AttributedString) {
        store.lock.withLock {
            if store.cache[key] == nil {
                store.order.append(key)
                if store.order.count > 64 { store.cache[store.order.removeFirst()] = nil }
            }
            store.cache[key] = value
        }
    }

    private static func code(_ text: String, language: String?) -> AttributedString? {
        store.lock.withLock {
            guard let engine = store.engine else { return nil }
            engine.setTheme(to: store.theme)
            guard let colored = engine.highlight(text, as: language) else { return nil }
            // The theme's characters must be the input's: a grammar that
            // rewrote anything (entity decoding gone wrong) is discarded.
            guard colored.string == text else { return nil }
            return colorsOnly(colored)
        }
    }

    /// Keep the grammar's foreground colors and bold, drop its fonts and
    /// everything else: the host sets the font (a font baked into the runs
    /// would silently beat it) and owns the background.
    private static func colorsOnly(_ source: NSAttributedString) -> AttributedString {
        var out = AttributedString()
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) {
            attributes, range, _ in
            var run = AttributedString(source.attributedSubstring(from: range).string)
            #if canImport(AppKit)
                if let color = attributes[.foregroundColor] as? NSColor {
                    run.foregroundColor = Color(nsColor: color)
                }
                if let font = attributes[.font] as? NSFont,
                    font.fontDescriptor.symbolicTraits.contains(.bold)
                {
                    run.inlinePresentationIntent = .stronglyEmphasized
                }
            #else
                if let color = attributes[.foregroundColor] as? UIColor {
                    run.foregroundColor = Color(uiColor: color)
                }
                if let font = attributes[.font] as? UIFont,
                    font.fontDescriptor.symbolicTraits.contains(.traitBold)
                {
                    run.inlinePresentationIntent = .stronglyEmphasized
                }
            #endif
            out += run
        }
        return out
    }
}

/// The block itself: monospaced, selectable, hugging its content. The host
/// brings the chrome (scroll bounds, background, padding) - two surfaces
/// showing the same evidence must color it identically, and this is how.
public struct SyntaxText: View {
    private let text: String
    private let format: CodeFormat
    private let font: Font

    /// `font` is a parameter, not an ambient: a font set ON the inner Text
    /// would silently beat any modifier the host applies outside, so the
    /// override point is explicit. Monospace is the default because code is.
    public init(
        _ text: String, format: CodeFormat,
        font: Font = .system(.callout, design: .monospaced)
    ) {
        self.text = text
        self.format = format
        self.font = font
    }

    public init(
        _ text: String, format raw: String?,
        font: Font = .system(.callout, design: .monospaced)
    ) {
        self.init(text, format: CodeFormat(raw), font: font)
    }

    public var body: some View {
        Text(Syntax.highlight(text, as: format))
            .font(font)
            // tvOS selects nothing: there is no pointer to drag across text.
            #if !os(tvOS)
                .textSelection(.enabled)
            #endif
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
