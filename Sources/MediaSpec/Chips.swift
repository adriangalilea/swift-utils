import Ink
import SwiftUI

// GRAMMAR V3: ARTWORK FIRST. The whole point of the family is proper
// iconography, so a chip is ONE MARK standing FRAMELESS - the artwork IS
// the chip. Badge artwork (HDR10, HDR10+, 4K, 8K, HD, SD) keeps its own
// box, a lockup keeps its shape, a symbol stands alone at the small rung.
// No pill, no disc, no kind glyph around a mark.
//
// A DRAWN word-badge exists only for a value with no artwork anywhere:
// 720p, HLG, channels (7.1), Remux, WEB-DL / WEBRip / HDTV / CAM, DTS:X,
// TrueHD when the Atmos lockup is already shown, AAC / PCM / ALAC / MP3 /
// MP2 / Vorbis, castellano / latino / a language code, every cut but IMAX.
// Its geometry is the HDR10 badge's: box ≈ 1.5 × cap height (the word's
// font is 0.62 × box, cap ≈ 0.7 × font), corner radius 0.25 × box, a
// stroke of 0.08 × box, semibold.
//
// PROVENANCE sits ON the mark: claim is ghosted (0.55 opacity); verified is
// full ink; measured is full ink over a soft `inkRest` wash capsule;
// delivered is the wash plus an `inkEdge` ring. Tone: `ink` follows the
// axis's foreground, `brand` paints a mark its official hex - unfilled
// weights only, never a near-black official colour (black on dark is a
// missing logo, not a brand statement); original-colour marks (the flag)
// ignore tone by construction.
//
// Two rungs, one threshold (`SpecChip.rail` = 32): at and above it lockups,
// below it the brand SYMBOLS (Dolby D, dts, the Blu-ray glyph, the flag)
// and the small badges. A strip groups per axis: `.inkTight` within an
// axis, `.inkGap` between axes; a delta trails the axis's last mark.

/// One mark's content: artwork from the catalog, or a word that has none.
public enum Glyph: Hashable, Sendable {
    case art(Mark)
    case word(String)
}

/// One glyph standing frameless, wearing its provenance. Public so a
/// consumer with an axis this product does not name (a container, a frame
/// rate) can still render it in the family's grammar.
public struct SpecChip: View {
    /// The height at and above which a chip wears lockups; below it, symbols.
    public static let rail: CGFloat = 32

    let glyph: Glyph
    let provenance: Provenance
    let height: CGFloat
    let tone: Tone

    public init(
        _ glyph: Glyph, provenance: Provenance = .verified, height: CGFloat = 34,
        tone: Tone = .ink
    ) {
        self.glyph = glyph
        self.provenance = provenance
        self.height = height
        self.tone = tone
    }

    /// The drawn word-badge - the one shape a value without artwork takes.
    public init(
        _ word: String, provenance: Provenance = .verified, height: CGFloat = 34,
        tone: Tone = .ink
    ) {
        self.init(.word(word), provenance: provenance, height: height, tone: tone)
    }

    public var body: some View {
        content
            .opacity(provenance == .claim ? 0.55 : 1)
            .padding(.horizontal, washed ? height * 0.18 : 0)
            .padding(.vertical, washed ? height * 0.12 : 0)
            .background {
                if washed { Capsule().fill(Color.inkRest) }
            }
            .overlay {
                if provenance == .delivered { Capsule().strokeBorder(Color.inkEdge, lineWidth: 1) }
            }
            .accessibilityLabel("\(accessibility), \(provenance.rawValue)")
    }

    @ViewBuilder
    private var content: some View {
        switch glyph {
        case .art(let m):
            BrandMark(m, height: height, tint: markTint(m))
        case .word(let w):
            Text(w)
                .font(.system(size: height * 0.62, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .padding(.horizontal, height * 0.26)
                .frame(height: height)
                .overlay {
                    RoundedRectangle(cornerRadius: height * 0.25)
                        .strokeBorder(ink, lineWidth: height * 0.08)
                }
        }
    }

    private var accessibility: String {
        switch glyph {
        case .art(let m): m.title
        case .word(let w): w
        }
    }

    private var ink: Color { .primary }
    private var washed: Bool { provenance == .measured || provenance == .delivered }

    /// THE TONE RULE. `ink` follows the axis. `brand` paints the mark its
    /// official hex on the unfilled weights only, and never a near-black
    /// one (luminance under 0.15 - Dolby, HDR10, DVD): black on a dark
    /// ground is a missing logo. The flag renders as authored regardless.
    private func markTint(_ m: Mark) -> Color {
        guard tone == .brand, !washed, m.luminance >= 0.15 else { return ink }
        return m.color
    }
}

/// The per-axis options every value chip and the strip share.
public struct ChipOptions: Sendable {
    public var provenance: Provenance = .verified
    public var height: CGFloat = 34
    public var delta: Delta? = nil
    public var detail: String? = nil
    public var tone: Tone = .ink

    var atRail: Bool { height >= SpecChip.rail }
    func glyph(_ marks: Marks) -> Glyph? {
        (atRail ? marks.lockup : marks.symbol).map(Glyph.art)
    }
}

/// One axis: its glyphs tight in a row, the delta trailing, the detail
/// beneath. Every value chip is this over its own glyph list.
struct Axis: View {
    let kind: Kind
    let glyphs: [Glyph]
    let accessibility: String
    let options: ChipOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: .inkTight) {
                ForEach(Array(glyphs.enumerated()), id: \.offset) { _, g in
                    SpecChip(
                        g, provenance: options.provenance, height: options.height,
                        tone: options.tone)
                }
                if let delta = options.delta {
                    Text(delta.glyph)
                        .font(.system(size: options.height * 0.4, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(delta.rawValue)
                }
            }
            if let detail = options.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: options.height * 0.3))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.rawValue): \(accessibility), \(options.provenance.rawValue)")
    }
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
        var glyphs: [Glyph] = []
        if let r = resolution { glyphs.append(options.glyph(r.marks) ?? .word(r.label)) }
        if let g = range, g != .sdr { glyphs.append(options.glyph(g.marks) ?? .word(g.label)) }
        return Axis(
            kind: .picture, glyphs: glyphs, accessibility: pictureLabel(resolution, range),
            options: options)
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
        var glyphs: [Glyph] = []
        // The object mark leads and, when it is artwork, the codec steps
        // down to a word (the Atmos lockup already says Dolby).
        var objectDrawn = false
        if let o = audio.object {
            let g = options.glyph(o.marks) ?? .word(o.label)
            if case .art = g { objectDrawn = true }
            glyphs.append(g)
        }
        glyphs.append(
            objectDrawn
                ? .word(audio.codec.label)
                : options.glyph(audio.codec.marks) ?? .word(audio.codec.label))
        if let c = audio.channels { glyphs.append(.word(c.label)) }
        return Axis(
            kind: .sound, glyphs: glyphs, accessibility: soundLabel(audio), options: options)
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
        var glyphs: [Glyph] = []
        if let art = options.glyph(tier.marks(at: resolution)) {
            glyphs.append(art)
            if tier == .remux { glyphs.append(.word(tier.label)) }
        } else {
            glyphs.append(.word(tier.label))
        }
        return Axis(kind: .tier, glyphs: glyphs, accessibility: tier.label, options: options)
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
        var glyphs: [Glyph] = []
        if let flag = options.glyph(lang.marks) {
            glyphs.append(flag)
            if options.atRail { glyphs.append(.word(lang.label)) }
        } else {
            glyphs.append(.word(lang.label))
        }
        return Axis(kind: .lang, glyphs: glyphs, accessibility: lang.label, options: options)
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
        Axis(
            kind: .cut, glyphs: [options.glyph(cut.marks) ?? .word(cut.label)],
            accessibility: cut.label, options: options)
    }
}

/// The spec as a row, fixed order picture · sound · tier · lang · cut,
/// absent axes omitted, `.inkGap` between axes (each axis packs its own
/// marks at `.inkTight`). One provenance and one tone for the strip: a
/// spec is one observation, not five. `deltas` trail a candidate's axes
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
            height: 24, tone: .brand)
    }
    .padding(.inkBlock)
    .background(Color.black)
}
