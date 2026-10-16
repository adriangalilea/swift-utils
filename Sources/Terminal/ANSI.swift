/// Raw ANSI escape primitives: ALWAYS ON, no TTY detection, no environment
/// checks. The vocabulary, not the policy: `ui` (Text.swift) decides WHETHER
/// to color; this is for output whose consumer renders ANSI regardless of
/// what stdout is (a status line, a file a terminal will cat).
///
/// 256-color escapes over 24-bit as the house default: the xterm cube is
/// stable across every terminal and multiplexer, 24-bit gets quantized or
/// dropped. `rgb` exists for a consumer known to render truecolor.
/// Same names and behaviour as ts-utils `universal/ansi` and py-utils `ansi`.
public enum ANSI {
    public static let reset = "\u{1B}[0m"
    public static let bold = "\u{1B}[1m"
    public static let dim = "\u{1B}[2m"
    public static let italic = "\u{1B}[3m"
    public static let underline = "\u{1B}[4m"

    /// Foreground, xterm-256 palette index.
    public static func fg(_ n: Int) -> String {
        precondition((0...255).contains(n), "xterm-256 index: \(n)")
        return "\u{1B}[38;5;\(n)m"
    }

    /// Background, xterm-256 palette index.
    public static func bg(_ n: Int) -> String {
        precondition((0...255).contains(n), "xterm-256 index: \(n)")
        return "\u{1B}[48;5;\(n)m"
    }

    /// Foreground, 24-bit: only when the consumer is known to render truecolor.
    public static func rgb(_ r: Int, _ g: Int, _ b: Int) -> String {
        precondition(
            [r, g, b].allSatisfy { (0...255).contains($0) }, "rgb components: \(r) \(g) \(b)")
        return "\u{1B}[38;2;\(r);\(g);\(b)m"
    }

    /// The string minus its style escapes.
    public static func strip(_ s: String) -> String {
        s.replacing(style, with: "")
    }

    /// One SGR style escape (`ESC [ … m`), the only kind this vocabulary emits.
    nonisolated(unsafe) static let style = /\x{1B}\[[0-9;]*m/
}
