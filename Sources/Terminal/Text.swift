import Foundation

/// Terminal text: the semantic palette, ANSI-aware measurement, clipping and
/// padding. Same names and behaviour as ts-utils `cli/text` and py-utils
/// `cli/text`, so a command line reads the same in every language.

/// The semantic palette: use these, not raw colors, so intent stays
/// consistent across every tool.
///
///     print(ui.head("Run echo?"), ui.muted("expires in 5m"))
public struct Palette: Sendable {
    /// Whether this palette paints at all. `ui` decides once per process.
    public let enabled: Bool

    public init(enabled: Bool) { self.enabled = enabled }

    /// The decision `ui` makes: the one rule (`ANSI.colorAsked`), and when the
    /// environment leaves it to the terminal, only when stdout AND stderr are
    /// terminals. A command line writes to both, so any redirection means some
    /// styled string may land in a file, and a file never gets escapes.
    public static func detected(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        ANSI.colorAsked(environment) ?? (isatty(STDOUT_FILENO) == 1 && isatty(STDERR_FILENO) == 1)
    }

    public func paint(_ open: String, _ s: String) -> String { enabled ? open + s + ANSI.reset : s }

    public func bold(_ s: String) -> String { paint(ANSI.bold, s) }
    public func dim(_ s: String) -> String { paint(ANSI.dim, s) }
    public func red(_ s: String) -> String { paint(ANSI.fg(1), s) }
    public func green(_ s: String) -> String { paint(ANSI.fg(2), s) }
    public func yellow(_ s: String) -> String { paint(ANSI.fg(3), s) }
    public func cyan(_ s: String) -> String { paint(ANSI.fg(6), s) }
    public func gray(_ s: String) -> String { paint(ANSI.fg(8), s) }

    /// A heading, the one thing to read first.
    public func head(_ s: String) -> String { bold(s) }
    /// What the line is about: a command, a name.
    public func accent(_ s: String) -> String { cyan(s) }
    /// Context the eye may skip: times, counts, provenance.
    public func muted(_ s: String) -> String { dim(s) }
    public func ok(_ s: String) -> String { green(s) }
    public func warn(_ s: String) -> String { yellow(s) }
    public func bad(_ s: String) -> String { red(s) }
    /// Ids and references, de-emphasized.
    public func ref(_ s: String) -> String { gray(s) }
}

/// The process's palette, decided once (`Palette.detected`).
public let ui = Palette(enabled: Palette.detected())

/// Visible width in terminal cells, style escapes stripped. A grapheme
/// cluster (one Swift `Character`: a ZWJ family, a flag, a skin tone) takes
/// two cells when East Asian wide or emoji-presented, one otherwise.
public func width(_ s: String) -> Int {
    ANSI.strip(s).reduce(0) { $0 + cells($1) }
}

/// Truncates to `n` visible cells with an ellipsis at the cut, ANSI-aware:
/// escapes pass through so styling survives, and an open style is closed
/// with a final reset. A wide character never straddles the cut.
public func clip(_ s: String, _ n: Int) -> String {
    if width(s) <= n { return s }
    var out = ""
    var used = 0
    var styled = false
    var rest = Substring(s)
    while !rest.isEmpty {
        if let match = rest.prefixMatch(of: ANSI.style) {
            out += match.output
            styled = true
            rest = rest[match.range.upperBound...]
            continue
        }
        let character = rest.removeFirst()
        let w = cells(character)
        guard used + w <= n - 1 else {
            out += "…"
            break
        }
        out.append(character)
        used += w
    }
    return styled && !out.hasSuffix(ANSI.reset) ? out + ANSI.reset : out
}

/// Pads on the right to `n` visible cells.
public func padEnd(_ s: String, _ n: Int) -> String {
    s + String(repeating: " ", count: max(0, n - width(s)))
}

/// Pads on the left to `n` visible cells.
public func padStart(_ s: String, _ n: Int) -> String {
    String(repeating: " ", count: max(0, n - width(s))) + s
}

/// East Asian Wide/Fullwidth blocks (the wcwidth core table).
private let wide: [ClosedRange<UInt32>] = [
    0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
    0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
    0xFFE0...0xFFE6, 0x20000...0x2FFFD, 0x30000...0x3FFFD,
]

/// Terminal cells one grapheme cluster occupies.
func cells(_ character: Character) -> Int {
    let scalars = character.unicodeScalars
    guard let first = scalars.first else { return 0 }
    if wide.contains(where: { $0.contains(first.value) }) { return 2 }
    let emoji = scalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
    return emoji ? 2 : 1
}
