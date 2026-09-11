import Ink
import SwiftUI

// The chips. One shape (Ink's Pill: the leading disc IS the cap), the
// value's MARK where it has one, words where it does not, and PROVENANCE
// AS WEIGHT - never a color, per the flare rule. A claim is a stroke with
// nothing inside; a verified fact rests; a measured one is raised; a
// delivered one is raised AND edged, its disc lit, because it is the only
// chip that speaks about THIS screen right now.
//
// TWO RUNGS, one threshold. At `SpecChip.rail` and above (34 is the
// default, 44 the couch) the LOCKUP replaces the word it stands for and
// the rest stays text: "4K" + the Dolby Vision logotype, the Dolby Atmos
// logotype + "TrueHD 7.1", the Blu-ray logotype + "Remux". Below it (the
// poster rung, 28 and under) the SYMBOL stands in: the double-D in the
// disc + "DV", the dts mark + "X", the HDR10+ badge alone. A symbol whose
// artwork is disc-shaped (aspect ≤ 1.6) takes the cap; a wide one runs
// inline like a lockup. Values without artwork render exactly as words.
//
// Sizes, tuned once: a lockup or inline symbol stands 0.50 × height
// (the label's font is 0.44 × height, so the mark's x-height lands on the
// text's cap height and a two-line lockup stays legible at 34); a symbol
// in the disc is inset 0.2 × height per side (0.6 × height across).

/// One piece of a chip's content: words, a mark, or a mark with a word
/// glued to its trailing edge (the dts wordmark + ":X").
public enum Part: Hashable, Sendable {
    case text(String)
    case mark(Mark)
    case marked(Mark, suffix: String)
}

/// The one chip body every kind wears. Public so a consumer with an axis
/// this product does not name (a container, a frame rate) can still render
/// it in the family's grammar.
public struct SpecChip: View {
    /// The height at and above which a chip wears lockups; below it, symbols.
    public static let rail: CGFloat = 32
    /// A symbol at most this wide-for-tall sits in the disc; wider ones
    /// run inline (the HDR10 badge, the Blu-ray glyph, IMAX).
    public static let discAspect: Double = 1.6

    let kind: Kind
    let parts: [Part]
    let symbol: Mark?
    let accessibility: String
    let provenance: Provenance
    let height: CGFloat
    let delta: Delta?
    let detail: String?
    let tone: Tone

    /// Words only - the shape every value without artwork takes.
    public init(
        _ kind: Kind, _ label: String, provenance: Provenance = .verified,
        height: CGFloat = 34, delta: Delta? = nil, detail: String? = nil, tone: Tone = .ink
    ) {
        self.init(
            kind, parts: [.text(label)], symbol: nil, accessibility: label,
            provenance: provenance, height: height, delta: delta, detail: detail, tone: tone)
    }

    /// Composed content. `symbol` takes the disc when disc-shaped, else it is
    /// prepended inline; `accessibility` is the full spoken label.
    public init(
        _ kind: Kind, parts: [Part], symbol: Mark?, accessibility: String,
        provenance: Provenance = .verified, height: CGFloat = 34, delta: Delta? = nil,
        detail: String? = nil, tone: Tone = .ink
    ) {
        self.kind = kind
        self.symbol = symbol
        self.accessibility = accessibility
        self.provenance = provenance
        self.height = height
        self.delta = delta
        self.detail = detail
        self.tone = tone
        if let symbol, symbol.aspect > SpecChip.discAspect {
            self.parts = [.mark(symbol)] + parts
        } else {
            self.parts = parts
        }
    }

    public var body: some View {
        Pill(height: height, tint: fill) {
            ZStack {
                Circle().fill(disc)
                if let symbol, symbol.aspect <= SpecChip.discAspect {
                    BrandMark(symbol, height: height * 0.6, tint: markTint(symbol))
                } else {
                    Image(systemName: kind.symbol)
                        .font(.system(size: height * 0.42, weight: .semibold))
                        .foregroundStyle(labelStyle)
                }
            }
        } content: {
            HStack(spacing: height * 0.18) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: height * 0.14) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            self.part(part)
                        }
                    }
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
        .accessibilityLabel("\(kind.rawValue): \(accessibility), \(provenance.rawValue)")
    }

    @ViewBuilder
    private func part(_ part: Part) -> some View {
        switch part {
        case .text(let s):
            label(s)
        case .mark(let m):
            BrandMark(m, height: height * 0.5, tint: markTint(m))
        case .marked(let m, let suffix):
            HStack(spacing: 0) {
                BrandMark(m, height: height * 0.5, tint: markTint(m))
                label(suffix)
            }
        }
    }

    private func label(_ s: String) -> some View {
        Text(s)
            .font(.system(size: height * 0.44, weight: provenance == .claim ? .regular : .semibold))
            .foregroundStyle(labelStyle)
            .lineLimit(1)
    }

    private var labelStyle: HierarchicalShapeStyle {
        provenance == .claim ? .secondary : .primary
    }

    /// THE TONE RULE. `ink` follows the label. `brand` paints the mark its
    /// official hex - but only on the unfilled weights (claim, verified):
    /// on a filled chip the mark stays in the label colour, one ink on one
    /// ground. And a brand whose official colour is near-black (Dolby,
    /// HDR10, DVD - luminance under 0.15) reads as ink too: black on a dark
    /// chip is not a brand statement, it is a missing logo. Original-colour
    /// marks (the flag) ignore all of this by construction.
    private func markTint(_ m: Mark) -> Color {
        let ink = provenance == .claim ? Color.secondary : Color.primary
        guard tone == .brand, !filled, m.luminance >= 0.15 else { return ink }
        return m.color
    }

    private var filled: Bool { provenance == .measured || provenance == .delivered }

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

/// The per-chip options every value chip and the strip share.
public struct ChipOptions: Sendable {
    public var provenance: Provenance = .verified
    public var height: CGFloat = 34
    public var delta: Delta? = nil
    public var detail: String? = nil
    public var tone: Tone = .ink

    var atRail: Bool { height >= SpecChip.rail }
}

public struct PictureChip: View {
    let resolution: Resolution?
    let range: DynamicRange?
    let options: ChipOptions

    public init(
        resolution: Resolution?, range: DynamicRange?, provenance: Provenance = .verified,
        height: CGFloat = 34, delta: Delta? = nil, detail: String? = nil, tone: Tone = .ink
    ) {
        self.resolution = resolution
        self.range = range
        self.options = ChipOptions(
            provenance: provenance, height: height, delta: delta, detail: detail, tone: tone)
    }

    public var body: some View {
        let rangeMarks = range?.marks ?? .none
        var parts: [Part] = []
        var symbol: Mark?
        if options.atRail {
            // "4K" + the range lockup; a 4K copy with no range lockup wears
            // the Ultra HD wordmark instead of the word.
            if let lockup = rangeMarks.lockup {
                if let r = resolution { parts.append(.text(r.label)) }
                parts.append(.mark(lockup))
            } else if let ultra = resolution?.marks.lockup {
                parts.append(.mark(ultra))
                if let g = range, g != .sdr { parts.append(.text(g.label)) }
            } else {
                parts.append(.text(pictureLabel(resolution, range)))
            }
        } else {
            symbol = rangeMarks.symbol
            if symbol != nil {
                // The symbol says the range; the short word beside it only
                // where the artwork alone is ambiguous (the double-D).
                if range == .dolbyVision { parts.append(.text(DynamicRange.dolbyVision.short)) }
            } else {
                parts.append(.text(pictureLabel(resolution, range, short: true)))
            }
        }
        return SpecChip(
            .picture, parts: parts, symbol: symbol, accessibility: pictureLabel(resolution, range),
            provenance: options.provenance, height: options.height, delta: options.delta,
            detail: options.detail, tone: options.tone)
    }
}

public struct SoundChip: View {
    let audio: Audio
    let options: ChipOptions

    public init(
        audio: Audio, provenance: Provenance = .verified, height: CGFloat = 34,
        delta: Delta? = nil, detail: String? = nil, tone: Tone = .ink
    ) {
        self.audio = audio
        self.options = ChipOptions(
            provenance: provenance, height: height, delta: delta, detail: detail, tone: tone)
    }

    public var body: some View {
        var parts: [Part] = []
        var symbol: Mark?
        let channels = audio.channels?.label
        if options.atRail {
            switch audio.object {
            case .atmos?:
                // The object lockup leads; the codec and layout stay words.
                parts.append(.mark(.dolbyatmos))
                parts.append(
                    .text([audio.codec.label, channels].compactMap { $0 }.joined(separator: " ")))
            case .dtsX?:
                // No DTS:X artwork exists anywhere: the dts wordmark + ":X".
                parts.append(.marked(.dtswordmark, suffix: ":X"))
                if let channels { parts.append(.text(channels)) }
            case nil:
                if let lockup = audio.codec.marks.lockup {
                    parts.append(.mark(lockup))
                    if let channels { parts.append(.text(channels)) }
                } else {
                    parts.append(.text(soundLabel(audio)))
                }
            }
        } else {
            switch audio.object {
            case .atmos?:
                symbol = .dolby
                parts.append(.text(ObjectAudio.atmos.label))
            case .dtsX?:
                symbol = .dts
                parts.append(.text("X"))
            case nil:
                symbol = audio.codec.marks.symbol
                let word = symbol == nil ? audio.codec.label : audio.codec.wordBesideSymbol
                if !word.isEmpty { parts.append(.text(word)) }
            }
        }
        return SpecChip(
            .sound, parts: parts, symbol: symbol, accessibility: soundLabel(audio),
            provenance: options.provenance, height: options.height, delta: options.delta,
            detail: options.detail, tone: options.tone)
    }
}

public struct TierChip: View {
    let tier: Tier
    let resolution: Resolution?
    let options: ChipOptions

    /// `resolution` lets a Blu-ray-sourced 4K copy wear the Ultra HD
    /// Blu-ray mark; the strip passes it, a lone chip may.
    public init(
        tier: Tier, resolution: Resolution? = nil, provenance: Provenance = .verified,
        height: CGFloat = 34, delta: Delta? = nil, detail: String? = nil, tone: Tone = .ink
    ) {
        self.tier = tier
        self.resolution = resolution
        self.options = ChipOptions(
            provenance: provenance, height: height, delta: delta, detail: detail, tone: tone)
    }

    public var body: some View {
        let marks = tier.marks(at: resolution)
        var parts: [Part] = []
        var symbol: Mark?
        if options.atRail {
            if let lockup = marks.lockup {
                parts.append(.mark(lockup))
                if tier == .remux { parts.append(.text(tier.label)) }
            } else {
                parts.append(.text(tier.label))
            }
        } else {
            symbol = marks.symbol
            if symbol == nil { parts.append(.text(tier.label)) }
        }
        return SpecChip(
            .tier, parts: parts, symbol: symbol, accessibility: tier.label,
            provenance: options.provenance, height: options.height, delta: options.delta,
            detail: options.detail, tone: options.tone)
    }
}

public struct LangChip: View {
    let lang: Lang
    let options: ChipOptions

    public init(
        lang: Lang, provenance: Provenance = .verified, height: CGFloat = 34,
        delta: Delta? = nil, detail: String? = nil, tone: Tone = .ink
    ) {
        self.lang = lang
        self.options = ChipOptions(
            provenance: provenance, height: height, delta: delta, detail: detail, tone: tone)
    }

    public var body: some View {
        let marks = lang.marks
        var parts: [Part] = []
        var symbol: Mark?
        if options.atRail, let flag = marks.lockup {
            parts = [.mark(flag), .text(lang.label)]
        } else if !options.atRail, let flag = marks.symbol {
            symbol = flag
        } else {
            parts = [.text(lang.label)]
        }
        return SpecChip(
            .lang, parts: parts, symbol: symbol, accessibility: lang.label,
            provenance: options.provenance, height: options.height, delta: options.delta,
            detail: options.detail, tone: options.tone)
    }
}

public struct CutChip: View {
    let cut: Cut
    let options: ChipOptions

    public init(
        cut: Cut, provenance: Provenance = .verified, height: CGFloat = 34,
        delta: Delta? = nil, detail: String? = nil, tone: Tone = .ink
    ) {
        self.cut = cut
        self.options = ChipOptions(
            provenance: provenance, height: height, delta: delta, detail: detail, tone: tone)
    }

    public var body: some View {
        let marks = cut.marks
        let mark = options.atRail ? marks.lockup : marks.symbol
        return SpecChip(
            .cut, parts: mark.map { [.mark($0)] } ?? [.text(cut.label)], symbol: nil,
            accessibility: cut.label, provenance: options.provenance, height: options.height,
            delta: options.delta, detail: options.detail, tone: options.tone)
    }
}

/// The spec as a row, fixed order picture · sound · tier · lang · cut,
/// absent axes omitted. One provenance and one tone for the strip: a spec
/// is one observation, not five. `deltas` decorate a candidate's axes
/// against the owned copy; `omit` is for surfaces that state an axis
/// elsewhere. The tier chip is handed the resolution so a 4K disc wears
/// the Ultra HD Blu-ray mark.
public struct MediaSpecStrip: View {
    let spec: MediaSpec
    let provenance: Provenance
    let height: CGFloat
    let deltas: [Kind: Delta]
    let omit: Set<Kind>
    let spacing: CGFloat
    let tone: Tone

    public init(
        spec: MediaSpec, provenance: Provenance = .verified, height: CGFloat = 34,
        deltas: [Kind: Delta] = [:], omit: Set<Kind> = [], spacing: CGFloat = .inkGap,
        tone: Tone = .ink
    ) {
        self.spec = spec
        self.provenance = provenance
        self.height = height
        self.deltas = deltas
        self.omit = omit
        self.spacing = spacing
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: spacing) {
            if !omit.contains(.picture), spec.resolution != nil || spec.range != nil {
                PictureChip(
                    resolution: spec.resolution, range: spec.range, provenance: provenance,
                    height: height, delta: deltas[.picture], tone: tone)
            }
            if !omit.contains(.sound), let audio = spec.audio {
                SoundChip(
                    audio: audio, provenance: provenance, height: height, delta: deltas[.sound],
                    tone: tone)
            }
            if !omit.contains(.tier), let tier = spec.tier {
                TierChip(
                    tier: tier, resolution: spec.resolution, provenance: provenance,
                    height: height, delta: deltas[.tier], tone: tone)
            }
            if !omit.contains(.lang), let lang = spec.lang {
                LangChip(
                    lang: lang, provenance: provenance, height: height, delta: deltas[.lang],
                    tone: tone)
            }
            if !omit.contains(.cut), let cut = spec.cut {
                CutChip(
                    cut: cut, provenance: provenance, height: height, delta: deltas[.cut],
                    tone: tone)
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
                    tier: .remux, lang: Lang("es-ES"), cut: .imax),
                provenance: p)
        }
        MediaSpecStrip(
            spec: MediaSpec(
                resolution: .p2160, range: .hdr10,
                audio: Audio(codec: .dtsHDMA, channels: .surround51), tier: .webdl),
            provenance: .claim,
            deltas: [.picture: .worse, .sound: .same, .tier: .worse])
        MediaSpecStrip(
            spec: MediaSpec(
                resolution: .p2160, range: .dolbyVision,
                audio: Audio(codec: .trueHD, channels: .surround71, object: .atmos),
                tier: .bluray, lang: Lang("es-ES")),
            height: 28, tone: .brand)
    }
    .padding(.inkBlock)
    .background(Color.black)
}
