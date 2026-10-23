import GitKit
import SwiftUI

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// The diff's inks, one set per ground. Added and removed are a quiet wash over the
/// line, a step stronger in the gutter, and a clear tint on the words that changed;
/// everything else is the primary ink at Ink's tiers, so a diff sits on a light page and
/// a dark one without a block of its own color.
struct DiffPalette: Sendable, Hashable {
    let added: Color
    let removed: Color
    let addedWash: Color
    let removedWash: Color
    let addedGutter: Color
    let removedGutter: Color
    let addedWord: Color
    let removedWord: Color
    let addedNumber: Color
    let removedNumber: Color
    let number: Color
    let marker: Color
    let text: Color
    let quiet: Color
    let hairline: Color
    let wash: Color
    let emptySide: Color
    let selection: Color
    let selectionEdge: Color

    static func of(_ scheme: ColorScheme) -> DiffPalette {
        scheme == .dark ? dark : light
    }

    // Hues chosen a little off the system green and red: the system's are signals, and a
    // diff is a page of them. Light grounds take a deeper hue at lower opacity, dark ones
    // a brighter hue at a touch more, so the wash reads the same weight on both.
    static let light = DiffPalette(
        added: Color(red: 0.10, green: 0.55, blue: 0.27),
        removed: Color(red: 0.80, green: 0.17, blue: 0.20),
        wash: (0.075, 0.13, 0.26), dark: false)

    static let dark = DiffPalette(
        added: Color(red: 0.36, green: 0.80, blue: 0.50),
        removed: Color(red: 0.98, green: 0.42, blue: 0.42),
        wash: (0.11, 0.17, 0.30), dark: true)

    private init(
        added: Color, removed: Color, wash: (line: Double, gutter: Double, word: Double), dark: Bool
    ) {
        self.added = added
        self.removed = removed
        addedWash = added.opacity(wash.line)
        removedWash = removed.opacity(wash.line)
        addedGutter = added.opacity(wash.gutter)
        removedGutter = removed.opacity(wash.gutter)
        addedWord = added.opacity(wash.word)
        removedWord = removed.opacity(wash.word)
        addedNumber = added.opacity(dark ? 0.85 : 0.8)
        removedNumber = removed.opacity(dark ? 0.85 : 0.8)
        number = .primary.opacity(dark ? 0.32 : 0.34)
        marker = .primary.opacity(0.45)
        text = .primary.opacity(dark ? 0.86 : 0.84)
        quiet = .primary.opacity(0.5)
        hairline = .primary.opacity(dark ? 0.12 : 0.1)
        self.wash = .primary.opacity(dark ? 0.05 : 0.035)
        emptySide = .primary.opacity(dark ? 0.035 : 0.025)
        selection = Color.accentColor.opacity(dark ? 0.22 : 0.16)
        selectionEdge = Color.accentColor.opacity(0.9)
    }

    func lineWash(_ kind: Git.Line.Kind) -> Color {
        switch kind {
        case .added: addedWash
        case .removed: removedWash
        case .context: .clear
        }
    }

    func gutterWash(_ kind: Git.Line.Kind) -> Color {
        switch kind {
        case .added: addedGutter
        case .removed: removedGutter
        case .context: .clear
        }
    }

    func word(_ kind: Git.Line.Kind) -> Color {
        kind == .added ? addedWord : removedWord
    }

    func numberInk(_ kind: Git.Line.Kind) -> Color {
        switch kind {
        case .added: addedNumber
        case .removed: removedNumber
        case .context: number
        }
    }
}

/// The facts of the code font at the size the reader chose: the size, a character's
/// advance (every width in a diff is a count of characters) and the line's height.
struct DiffMetrics: Hashable, Sendable {
    let size: CGFloat
    let advance: CGFloat
    let lineHeight: CGFloat

    var font: Font { .system(size: size, design: .monospaced) }
    var smallFont: Font { .system(size: size * 0.92, design: .monospaced) }

    /// Columns of code in points.
    func width(_ columns: Int) -> CGFloat { CGFloat(columns) * advance }

    @MainActor private static var known: [String: DiffMetrics] = [:]

    @MainActor static func of(size explicit: CGFloat?, _ typeSize: DynamicTypeSize) -> DiffMetrics {
        let key = "\(explicit ?? -1)|\(typeSize)"
        if let hit = known[key] { return hit }
        #if canImport(UIKit)
            let size =
                explicit
                ?? UIFont.preferredFont(
                    forTextStyle: .footnote,
                    compatibleWith: UITraitCollection(preferredContentSizeCategory: .init(typeSize))
                ).pointSize
            let font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #else
            // A Mac's code is set at Xcode's size: the body text style is 13, code reads
            // best a point under it.
            let size = explicit ?? 12
            let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #endif
        let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
        let metrics = DiffMetrics(size: size, advance: advance, lineHeight: (size * 1.55).rounded())
        known[key] = metrics
        return metrics
    }
}

#if canImport(UIKit)
    extension UIContentSizeCategory {
        init(_ size: DynamicTypeSize) {
            self =
                switch size {
                case .xSmall: .extraSmall
                case .small: .small
                case .medium: .medium
                case .large: .large
                case .xLarge: .extraLarge
                case .xxLarge: .extraExtraLarge
                case .xxxLarge: .extraExtraExtraLarge
                case .accessibility1: .accessibilityMedium
                case .accessibility2: .accessibilityLarge
                case .accessibility3: .accessibilityExtraLarge
                case .accessibility4: .accessibilityExtraExtraLarge
                case .accessibility5: .accessibilityExtraExtraExtraLarge
                @unknown default: .large
                }
        }
    }
#endif
