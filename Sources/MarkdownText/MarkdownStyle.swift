import SwiftUI

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// How a markdown text is set: the text style its words are in, the ink they wear, and
/// whether it is a whole page or a preview cut to a few lines. A value in the
/// environment (`.markdownStyle(_:)`), so one `MarkdownView` serves the body of a
/// message, its dimmed footnote and a list row's preview.
///
/// Every measure is stated in the unit the reader feels and derived from the font the
/// text is actually set in (`Metrics`): line height as a multiple of the size, block
/// spacing and indents in ems, the measure in characters. Nothing is a point count tuned
/// to one screen, so the page is the same page at every Dynamic Type size.
public struct MarkdownStyle: Sendable, Hashable {
    /// The words' text style. Every other size (headings, code, a table) is a share of
    /// it, so a footnote-sized text is the same page made small.
    public var textStyle: Font.TextStyle
    public var ink: Ink
    /// A preview: the whole text as one run cut at this many lines. Nil draws the page.
    public var lineLimit: Int?
    /// The longest line, in characters of the text's own font; past it the text keeps
    /// its measure and the space beside it is the host's. Nil runs to the width given.
    public var measure: Int?

    public init(
        textStyle: Font.TextStyle = .body, ink: Ink = .primary, lineLimit: Int? = nil,
        measure: Int? = 72
    ) {
        self.textStyle = textStyle
        self.ink = ink
        self.lineLimit = lineLimit
        self.measure = measure
    }

    /// A message's body: the reading text.
    public static let body = MarkdownStyle()
    /// A quiet aside: footnote size, the secondary ink.
    public static let footnote = MarkdownStyle(textStyle: .footnote, ink: .secondary)

    /// This style as a preview of `lines` lines.
    public func preview(lines: Int) -> MarkdownStyle {
        var copy = self
        copy.lineLimit = lines
        return copy
    }

    /// The ink ladder: one color, the primary, at the tiers ui's markdown wears (titles
    /// near full, the words a step under, markers and what is struck quiet, every line a
    /// hairline and every surface a wash). Right on a light ground and a dark one,
    /// because it is the primary ink of either.
    public enum Ink: Sendable, Hashable {
        case primary, secondary

        var titles: Color { .primary.opacity(self == .primary ? 0.95 : 0.7) }
        var words: Color { .primary.opacity(self == .primary ? 0.82 : 0.6) }
        var quiet: Color { .primary.opacity(self == .primary ? 0.45 : 0.38) }
        var hairline: Color { .primary.opacity(0.1) }
        var wash: Color { .primary.opacity(0.045) }
    }
}

extension EnvironmentValues {
    @Entry public var markdownStyle: MarkdownStyle = .body
}

extension View {
    public func markdownStyle(_ style: MarkdownStyle) -> some View {
        environment(\.markdownStyle, style)
    }
}

/// The facts of the font a text is set in, read from the system at the size the reader
/// chose: everything the page measures is a multiple of these.
struct Metrics: Hashable {
    /// The font's size: 1em.
    let em: CGFloat
    /// The font's own line height, in ems (the system's is about 1.2: set for labels).
    let natural: CGFloat
    /// The width of an average character of running text, in ems: a measure in
    /// characters is this times the count.
    let ch: CGFloat
    /// The width of a digit, in ems: an ordered list's numbers stand in a column of them.
    let digit: CGFloat

    /// Line height as a multiple of the size: open enough to read a long answer set at a
    /// regular weight.
    static let leading: CGFloat = 1.45

    /// `x` ems, in points.
    func em(_ x: CGFloat) -> CGFloat { x * em }

    /// The space to add between the lines of text set at `size` points so its line
    /// height is `leading` (the page's own when nil) times the size.
    func lineSpacing(at size: CGFloat, leading: CGFloat = Metrics.leading) -> CGFloat {
        max(0, size * (leading - natural))
    }

    /// The same font at `factor` of the size: a footnote's text, a table's.
    func scaled(_ factor: CGFloat) -> Metrics {
        Metrics(em: em * factor, natural: natural, ch: ch, digit: digit)
    }

    private init(em: CGFloat, natural: CGFloat, ch: CGFloat, digit: CGFloat) {
        self.em = em
        self.natural = natural
        self.ch = ch
        self.digit = digit
    }

    @MainActor private static var read: [String: Metrics] = [:]

    /// The text style's font at the reader's size, read once per style and size.
    @MainActor static func of(_ style: Font.TextStyle, _ size: DynamicTypeSize) -> Metrics {
        let key = "\(style)|\(size)"
        if let known = read[key] { return known }
        #if canImport(UIKit)
            let font = UIFont.preferredFont(
                forTextStyle: style.platform,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .init(size)))
        #else
            let font = NSFont.preferredFont(forTextStyle: style.platform)
        #endif
        let sentence = "the quick brown fox jumps over a lazy dog"
        let width = { (s: String) in (s as NSString).size(withAttributes: [.font: font]).width }
        let em = font.pointSize
        let metrics = Metrics(
            em: em, natural: (font.ascender - font.descender + font.leading) / em,
            ch: width(sentence) / CGFloat(sentence.count) / em, digit: width("0") / em)
        read[key] = metrics
        return metrics
    }
}

extension Font.TextStyle {
    #if canImport(UIKit)
        var platform: UIFont.TextStyle {
            switch self {
            case .largeTitle:
                #if os(tvOS)
                    .title1
                #else
                    .largeTitle
                #endif
            case .title: .title1
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .subheadline: .subheadline
            case .body: .body
            case .callout: .callout
            case .footnote: .footnote
            case .caption: .caption1
            case .caption2: .caption2
            @unknown default: .body
            }
        }
    #else
        var platform: NSFont.TextStyle {
            switch self {
            case .largeTitle: .largeTitle
            case .title: .title1
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .subheadline: .subheadline
            case .body: .body
            case .callout: .callout
            case .footnote: .footnote
            case .caption: .caption1
            case .caption2: .caption2
            @unknown default: .body
            }
        }
    #endif
}
