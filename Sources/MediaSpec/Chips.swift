import Ink
import SwiftUI

// The chips. One shape (Ink's Pill: the leading disc IS the cap), one kind
// glyph in the disc, the label beside it, and PROVENANCE AS WEIGHT - never
// a color, per the flare rule. A claim is a stroke with nothing inside; a
// verified fact rests; a measured one is raised; a delivered one is raised
// AND edged, its disc lit, because it is the only chip that speaks about
// THIS screen right now.

/// The one chip body every kind wears. Public so a consumer with an axis
/// this product does not name (a container, a frame rate) can still render
/// it in the family's grammar.
public struct SpecChip: View {
    let kind: Kind
    let label: String
    let provenance: Provenance
    let height: CGFloat
    let delta: Delta?
    let detail: String?

    public init(
        _ kind: Kind, _ label: String, provenance: Provenance = .verified,
        height: CGFloat = 34, delta: Delta? = nil, detail: String? = nil
    ) {
        self.kind = kind
        self.label = label
        self.provenance = provenance
        self.height = height
        self.delta = delta
        self.detail = detail
    }

    public var body: some View {
        Pill(height: height, tint: fill) {
            ZStack {
                Circle().fill(disc)
                Image(systemName: kind.symbol)
                    .font(.system(size: height * 0.42, weight: .semibold))
                    .foregroundStyle(provenance == .claim ? .secondary : .primary)
            }
        } content: {
            HStack(spacing: height * 0.18) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(
                            .system(
                                size: height * 0.44,
                                weight: provenance == .claim ? .regular : .semibold)
                        )
                        .foregroundStyle(provenance == .claim ? .secondary : .primary)
                        .lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: height * 0.3))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let delta {
                    Text(delta.glyph)
                        .font(.system(size: height * 0.36, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(delta.rawValue)
                }
            }
        }
        .overlay {
            if stroked {
                Capsule().strokeBorder(Color.inkEdge, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.rawValue): \(label), \(provenance.rawValue)")
    }

    private var fill: Color {
        switch provenance {
        case .claim: .clear
        case .verified: .inkRest
        case .measured, .delivered: .inkRaised
        }
    }

    private var disc: Color {
        switch provenance {
        case .claim: .clear
        case .verified: .inkRest
        case .measured: .inkRaised
        case .delivered: .inkSelection
        }
    }

    private var stroked: Bool { provenance == .claim || provenance == .delivered }
}

public struct PictureChip: View {
    let resolution: Resolution?
    let range: DynamicRange?
    let provenance: Provenance
    let height: CGFloat
    let delta: Delta?
    let detail: String?

    public init(
        resolution: Resolution?, range: DynamicRange?, provenance: Provenance = .verified,
        height: CGFloat = 34, delta: Delta? = nil, detail: String? = nil
    ) {
        self.resolution = resolution
        self.range = range
        self.provenance = provenance
        self.height = height
        self.delta = delta
        self.detail = detail
    }

    public var body: some View {
        SpecChip(
            .picture, pictureLabel(resolution, range), provenance: provenance, height: height,
            delta: delta, detail: detail)
    }
}

public struct SoundChip: View {
    let audio: Audio
    let provenance: Provenance
    let height: CGFloat
    let delta: Delta?
    let detail: String?

    public init(
        audio: Audio, provenance: Provenance = .verified, height: CGFloat = 34,
        delta: Delta? = nil, detail: String? = nil
    ) {
        self.audio = audio
        self.provenance = provenance
        self.height = height
        self.delta = delta
        self.detail = detail
    }

    public var body: some View {
        SpecChip(
            .sound, soundLabel(audio), provenance: provenance, height: height, delta: delta,
            detail: detail)
    }
}

public struct TierChip: View {
    let tier: Tier
    let provenance: Provenance
    let height: CGFloat
    let delta: Delta?
    let detail: String?

    public init(
        tier: Tier, provenance: Provenance = .verified, height: CGFloat = 34,
        delta: Delta? = nil, detail: String? = nil
    ) {
        self.tier = tier
        self.provenance = provenance
        self.height = height
        self.delta = delta
        self.detail = detail
    }

    public var body: some View {
        SpecChip(
            .tier, tier.label, provenance: provenance, height: height, delta: delta,
            detail: detail)
    }
}

public struct LangChip: View {
    let lang: Lang
    let provenance: Provenance
    let height: CGFloat
    let delta: Delta?
    let detail: String?

    public init(
        lang: Lang, provenance: Provenance = .verified, height: CGFloat = 34,
        delta: Delta? = nil, detail: String? = nil
    ) {
        self.lang = lang
        self.provenance = provenance
        self.height = height
        self.delta = delta
        self.detail = detail
    }

    public var body: some View {
        SpecChip(
            .lang, lang.label, provenance: provenance, height: height, delta: delta,
            detail: detail)
    }
}

public struct CutChip: View {
    let cut: Cut
    let provenance: Provenance
    let height: CGFloat
    let delta: Delta?
    let detail: String?

    public init(
        cut: Cut, provenance: Provenance = .verified, height: CGFloat = 34,
        delta: Delta? = nil, detail: String? = nil
    ) {
        self.cut = cut
        self.provenance = provenance
        self.height = height
        self.delta = delta
        self.detail = detail
    }

    public var body: some View {
        SpecChip(
            .cut, cut.label, provenance: provenance, height: height, delta: delta,
            detail: detail)
    }
}

/// The spec as a row, fixed order picture · sound · tier · lang · cut,
/// absent axes omitted. One provenance for the strip: a spec is one
/// observation, not five. `deltas` decorate a candidate's axes against the
/// owned copy; `omit` is for surfaces that state an axis elsewhere.
public struct MediaSpecStrip: View {
    let spec: MediaSpec
    let provenance: Provenance
    let height: CGFloat
    let deltas: [Kind: Delta]
    let omit: Set<Kind>
    let spacing: CGFloat

    public init(
        spec: MediaSpec, provenance: Provenance = .verified, height: CGFloat = 34,
        deltas: [Kind: Delta] = [:], omit: Set<Kind> = [], spacing: CGFloat = .inkGap
    ) {
        self.spec = spec
        self.provenance = provenance
        self.height = height
        self.deltas = deltas
        self.omit = omit
        self.spacing = spacing
    }

    public var body: some View {
        HStack(spacing: spacing) {
            if !omit.contains(.picture), spec.resolution != nil || spec.range != nil {
                PictureChip(
                    resolution: spec.resolution, range: spec.range, provenance: provenance,
                    height: height, delta: deltas[.picture])
            }
            if !omit.contains(.sound), let audio = spec.audio {
                SoundChip(
                    audio: audio, provenance: provenance, height: height, delta: deltas[.sound])
            }
            if !omit.contains(.tier), let tier = spec.tier {
                TierChip(tier: tier, provenance: provenance, height: height, delta: deltas[.tier])
            }
            if !omit.contains(.lang), let lang = spec.lang {
                LangChip(lang: lang, provenance: provenance, height: height, delta: deltas[.lang])
            }
            if !omit.contains(.cut), let cut = spec.cut {
                CutChip(cut: cut, provenance: provenance, height: height, delta: deltas[.cut])
            }
        }
    }
}

#Preview("MediaSpec") {
    VStack(alignment: .leading, spacing: .inkLane) {
        ForEach(Provenance.allCases, id: \.self) { p in
            MediaSpecStrip(
                spec: MediaSpec(
                    resolution: .p2160, range: .dolbyVision,
                    audio: Audio(codec: .trueHD, channels: .surround71, object: .atmos),
                    tier: .remux, lang: Lang("es-ES"), cut: .extended),
                provenance: p)
        }
        MediaSpecStrip(
            spec: MediaSpec(
                resolution: .p2160, range: .hdr10,
                audio: Audio(codec: .dtsHDMA, channels: .surround51), tier: .webdl),
            provenance: .claim,
            deltas: [.picture: .worse, .sound: .same, .tier: .worse])
    }
    .padding(.inkBlock)
    .background(Color.black)
}
