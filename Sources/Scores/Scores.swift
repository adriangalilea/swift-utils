import Ink
import SwiftUI

// The SCORE vocabulary: one chip per source wearing its source's REAL
// brand mark (BrandMark over the generated `Brand` enum - artwork and
// official colors both from upstream, never hand-transcribed here)
// beside the value in that source's OWN scale. Two deliberate exceptions
// where the brand IS a shape, and they are exactly the two whose official
// color is unusable on a dark surface: Metacritic's colored box that IS
// the number (#000000), and Letterboxd's tri-color dots (#202830, and a
// mono glyph would lose the three colors). Composable: a strip is chips
// in a row; consumers pick which sources ride.

public enum ScoreSource: String, Sendable {
    case imdb          // 0-10
    case rtCritic      // 0-100
    case rtAudience    // 0-100
    case metacritic    // 0-100
    case letterboxd    // 0-10
    case tmdb          // 0-10
    case user          // 0-10, the personal star
}

public struct ScoreChip: View {
    let source: ScoreSource
    let value: Double

    public init(_ source: ScoreSource, _ value: Double) {
        self.source = source
        self.value = value
    }

    public var body: some View {
        switch source {
        case .imdb:
            HStack(spacing: 7) {
                BrandMark(Brand.imdb, height: 26)
                Text(one(value)).font(.callout.weight(.semibold)).monospacedDigit()
            }
        case .rtCritic, .rtAudience:
            HStack(spacing: 7) {
                // Fresh wears the tomato, rotten the splat green - the one
                // place a semantic tint overrides the brand's own color.
                BrandMark(Brand.rottentomatoes, height: 22,
                          tint: value >= 60 ? nil : Color(red: 0.42, green: 0.62, blue: 0.14))
                Text("\(Int(value))%").font(.callout.weight(.semibold)).monospacedDigit()
            }
        case .metacritic:
            // The colored box IS the number - the band is the verdict.
            Text("\(Int(value))")
                .font(.callout.weight(.bold)).monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 48, height: 34)
                .background(
                    value >= 61 ? Color(red: 0.40, green: 0.80, blue: 0.20)
                        : value >= 40 ? Color(red: 1.00, green: 0.80, blue: 0.20)
                        : Color(red: 1.00, green: 0.27, blue: 0.23),
                    in: RoundedRectangle(cornerRadius: .inkChip)
                )
        case .letterboxd:
            HStack(spacing: 6) {
                HStack(spacing: -4) {
                    Circle().fill(Color(red: 1.00, green: 0.50, blue: 0.00)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.00, green: 0.88, blue: 0.33)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.25, green: 0.74, blue: 0.96)).frame(width: 12, height: 12)
                }
                Text(one(value)).font(.callout.weight(.semibold)).monospacedDigit()
            }
        case .tmdb:
            HStack(spacing: 7) {
                BrandMark(Brand.themoviedatabase, height: 18)
                Text(one(value)).font(.callout.weight(.semibold)).monospacedDigit()
            }
        case .user:
            HStack(spacing: 5) {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(Color.accentColor)
                Text(one(value)).font(.callout.weight(.semibold)).monospacedDigit()
            }
        }
    }

    private func one(_ v: Double) -> String { String(format: "%.1f", v) }
}

/// Chips in a row - the poster-strip / meta-line composition.
public struct ScoreStrip: View {
    let entries: [(ScoreSource, Double)]
    let spacing: CGFloat

    public init(_ entries: [(ScoreSource, Double)], spacing: CGFloat = 18) {
        self.entries = entries
        self.spacing = spacing
    }

    public var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                ScoreChip(e.0, e.1)
            }
        }
    }
}
