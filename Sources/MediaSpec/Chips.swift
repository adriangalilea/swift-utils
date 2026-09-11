import Ink
import SwiftUI

// ARTWORK FIRST. The whole point of the family is proper iconography, so a
// chip is ONE MARK standing FRAMELESS - the artwork IS the chip. A brand
// lockup keeps its shape, a brand symbol stands alone at the small rung.
// No pill, no disc, no kind glyph around a mark.
//
// EVERY BOXED VALUE IS ONE WEIGHT. 720p, HDR10 / HDR10+ / HLG, channels
// (7.1), Remux, WEB-DL / WEBRip / HDTV / CAM, DTS:X, codec words (TrueHD
// beside the Atmos lockup, AAC / PCM / ALAC / MP3 / MP2 / Vorbis), a
// language's display name, every cut but IMAX are DRAWN: box height = chip
// height h, corner radius 0.25h, stroke 0.08h, side pad 0.26h, word 0.62h
// semibold (cap ≈ 0.7 × font, so box ≈ 1.5 × cap, the HDR10 badge's own
// proportion). SD / HD / 4K / 8K are tabler's badge ARTWORK, because 4K
// and 8K need real distinction and its letterforms give it - restroked to
// 1.12 on the 24-grid (1.12 / the 14-unit box = 0.08h) and rendered with
// the box at h (`Mark.boxScale`), so the drawn and the drawn-by-tabler
// badge are one weight by construction.
//
// EMPHASIS sits ON the mark and is named for the look alone: ghost (0.55
// opacity), plain (full ink, no ground), washed (an `inkRest` capsule
// behind), ringed (the wash plus an `inkEdge` ring). TONE: `ink` follows
// the axis's foreground, `brand` paints a mark its official hex - on the
// unwashed emphases only, and never a near-black official colour (black on
// dark is a missing logo, not a brand statement); original-colour marks
// (the flag) ignore tone by construction. A TRAILING slot after an axis's
// last mark takes any view the consumer wants there.
//
// Two rungs, one threshold (`SpecChip.rail` = 32): at and above it lockups,
// below it the brand SYMBOLS (Dolby D, dts, the Blu-ray glyph, the flag);
// drawn badges are the same at both. A strip groups per axis: `.inkTight`
// within an axis, `.inkGap` between axes.

/// One mark's content: artwork from the catalog, or a word that has none.
public enum Glyph: Hashable, Sendable {
    case art(Mark)
    case word(String)
}

/// One glyph standing frameless, wearing its emphasis. Public so a
/// consumer with an axis this product does not name (a container, a frame
/// rate) can still render it in the family's grammar.
public struct SpecChip: View {
    /// The height at and above which a chip wears lockups; below it, symbols.
    public static let rail: CGFloat = 32

    let glyph: Glyph
    let emphasis: Emphasis
    let height: CGFloat
    let tone: Tone

    public init(
        _ glyph: Glyph, emphasis: Emphasis = .plain, height: CGFloat = 34, tone: Tone = .ink
    ) {
        self.glyph = glyph
        self.emphasis = emphasis
        self.height = height
        self.tone = tone
    }

    /// The drawn word-badge - the one shape a value without artwork takes.
    public init(
        _ word: String, emphasis: Emphasis = .plain, height: CGFloat = 34, tone: Tone = .ink
    ) {
        self.init(.word(word), emphasis: emphasis, height: height, tone: tone)
    }

    public var body: some View {
        content
            .opacity(emphasis == .ghost ? 0.55 : 1)
            .padding(.horizontal, washed ? height * 0.18 : 0)
            .padding(.vertical, washed ? height * 0.12 : 0)
            .background {
                if washed { Capsule().fill(Color.inkRest) }
            }
            .overlay {
                if emphasis == .ringed { Capsule().strokeBorder(Color.inkEdge, lineWidth: 1) }
            }
            .accessibilityLabel(accessibility)
    }

    @ViewBuilder
    private var content: some View {
        switch glyph {
        case .art(let m):
            // A file whose drawn box is smaller than its grid renders taller
            // so the BOX, not the grid, lands at the chip height.
            BrandMark(m, height: height * m.boxScale, tint: markTint(m))
                .frame(height: height)
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
    private var washed: Bool { emphasis == .washed || emphasis == .ringed }

    /// THE TONE RULE. `ink` follows the axis. `brand` paints the mark its
    /// official hex on the unwashed emphases only, and never a near-black
    /// one (luminance under 0.15 - Dolby, HDR10, DVD): black on a dark
    /// ground is a missing logo. The flag renders as authored regardless.
    private func markTint(_ m: Mark) -> Color {
        guard tone == .brand, !washed, m.luminance >= 0.15 else { return ink }
        return m.color
    }
}

/// The per-axis options every value chip and the strip share.
public struct ChipOptions {
    public var emphasis: Emphasis = .plain
    public var height: CGFloat = 34
    public var trailing: AnyView? = nil
    public var detail: String? = nil
    public var tone: Tone = .ink

    var atRail: Bool { height >= SpecChip.rail }
    func glyph(_ marks: Marks) -> Glyph? {
        (atRail ? marks.lockup : marks.symbol).map(Glyph.art)
    }
}

/// One axis: its glyphs tight in a row, the trailing slot after them, the
/// detail beneath. Every value chip is this over its own glyph list.
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
                        g, emphasis: options.emphasis, height: options.height, tone: options.tone)
                }
                if let trailing = options.trailing { trailing }
            }
            if let detail = options.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: options.height * 0.3))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind.rawValue): \(accessibility)")
    }
}

public struct PictureChip: View {
    let resolution: Resolution?
    let range: DynamicRange?
    let options: ChipOptions

    public init(
        resolution: Resolution?, range: DynamicRange?, emphasis: Emphasis = .plain,
        height: CGFloat = 34, trailing: AnyView? = nil, detail: String? = nil, tone: Tone = .ink
    ) {
        self.resolution = resolution
        self.range = range
        self.options = ChipOptions(
            emphasis: emphasis, height: height, trailing: trailing, detail: detail, tone: tone)
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
        audio: Audio, emphasis: Emphasis = .plain, height: CGFloat = 34,
        trailing: AnyView? = nil, detail: String? = nil, tone: Tone = .ink
    ) {
        self.audio = audio
        self.options = ChipOptions(
            emphasis: emphasis, height: height, trailing: trailing, detail: detail, tone: tone)
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

    /// `resolution` lets a Blu-ray-sourced 4K spec wear the Ultra HD
    /// Blu-ray mark; the strip passes it, a lone chip may.
    public init(
        tier: Tier, resolution: Resolution? = nil, emphasis: Emphasis = .plain,
        height: CGFloat = 34, trailing: AnyView? = nil, detail: String? = nil, tone: Tone = .ink
    ) {
        self.tier = tier
        self.resolution = resolution
        self.options = ChipOptions(
            emphasis: emphasis, height: height, trailing: trailing, detail: detail, tone: tone)
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
    let label: String?
    let options: ChipOptions

    /// `label` overrides the system display name with the consumer's own
    /// spelling.
    public init(
        lang: Lang, label: String? = nil, emphasis: Emphasis = .plain, height: CGFloat = 34,
        trailing: AnyView? = nil, detail: String? = nil, tone: Tone = .ink
    ) {
        self.lang = lang
        self.label = label
        self.options = ChipOptions(
            emphasis: emphasis, height: height, trailing: trailing, detail: detail, tone: tone)
    }

    public var body: some View {
        let word = label ?? lang.label
        var glyphs: [Glyph] = []
        if let flag = options.glyph(lang.marks) {
            glyphs.append(flag)
            if options.atRail { glyphs.append(.word(word)) }
        } else {
            glyphs.append(.word(word))
        }
        return Axis(kind: .lang, glyphs: glyphs, accessibility: word, options: options)
    }
}

public struct CutChip: View {
    let cut: Cut
    let options: ChipOptions

    public init(
        cut: Cut, emphasis: Emphasis = .plain, height: CGFloat = 34, trailing: AnyView? = nil,
        detail: String? = nil, tone: Tone = .ink
    ) {
        self.cut = cut
        self.options = ChipOptions(
            emphasis: emphasis, height: height, trailing: trailing, detail: detail, tone: tone)
    }

    public var body: some View {
        Axis(
            kind: .cut, glyphs: [options.glyph(cut.marks) ?? .word(cut.label)],
            accessibility: cut.label, options: options)
    }
}

/// The spec as a row, fixed order picture · sound · tier · lang · cut,
/// absent axes omitted, `.inkGap` between axes (each axis packs its own
/// marks at `.inkTight`). One emphasis and one tone for the strip.
/// `adornments` are trailing views per axis; `labels` overrides the
/// language's display name; `omit` is for surfaces that state an axis
/// elsewhere. The tier chip is handed the resolution so a 4K disc wears
/// the Ultra HD Blu-ray mark.
public struct MediaSpecStrip: View {
    let spec: MediaSpec
    let emphasis: Emphasis
    let height: CGFloat
    let adornments: [Kind: AnyView]
    let langLabel: String?
    let omit: Set<Kind>
    let spacing: CGFloat
    let tone: Tone

    public init(
        spec: MediaSpec, emphasis: Emphasis = .plain, height: CGFloat = 34,
        adornments: [Kind: AnyView] = [:], langLabel: String? = nil, omit: Set<Kind> = [],
        spacing: CGFloat = .inkGap, tone: Tone = .ink
    ) {
        self.spec = spec
        self.emphasis = emphasis
        self.height = height
        self.adornments = adornments
        self.langLabel = langLabel
        self.omit = omit
        self.spacing = spacing
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: spacing) {
            if !omit.contains(.picture), spec.resolution != nil || spec.range != nil {
                PictureChip(
                    resolution: spec.resolution, range: spec.range, emphasis: emphasis,
                    height: height, trailing: adornments[.picture], tone: tone)
            }
            if !omit.contains(.sound), let audio = spec.audio {
                SoundChip(
                    audio: audio, emphasis: emphasis, height: height,
                    trailing: adornments[.sound], tone: tone)
            }
            if !omit.contains(.tier), let tier = spec.tier {
                TierChip(
                    tier: tier, resolution: spec.resolution, emphasis: emphasis, height: height,
                    trailing: adornments[.tier], tone: tone)
            }
            if !omit.contains(.lang), let lang = spec.lang {
                LangChip(
                    lang: lang, label: langLabel, emphasis: emphasis, height: height,
                    trailing: adornments[.lang], tone: tone)
            }
            if !omit.contains(.cut), let cut = spec.cut {
                CutChip(
                    cut: cut, emphasis: emphasis, height: height, trailing: adornments[.cut],
                    tone: tone)
            }
        }
    }
}

#Preview("MediaSpec") {
    VStack(alignment: .leading, spacing: .inkLane) {
        ForEach(Emphasis.allCases, id: \.self) { e in
            MediaSpecStrip(
                spec: MediaSpec(
                    resolution: .p2160, range: .dolbyVision,
                    audio: Audio(codec: .trueHD, channels: .surround71, object: .atmos),
                    tier: .remux, lang: Lang("es-ES"), cut: .imax),
                emphasis: e)
        }
        MediaSpecStrip(
            spec: MediaSpec(
                resolution: .p2160, range: .hdr10,
                audio: Audio(codec: .dtsHDMA, channels: .surround51), tier: .webdl),
            emphasis: .ghost,
            adornments: [.picture: AnyView(Text("▼")), .sound: AnyView(Text("="))])
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
