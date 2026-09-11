import Ink
import SwiftUI

// ARTWORK FIRST. The whole point of the family is proper iconography, so a
// chip is ONE MARK standing FRAMELESS - the artwork IS the chip. A brand
// lockup keeps its shape, a brand symbol stands alone at the small rung.
// No pill, no disc, no kind glyph around a mark.
//
// EVERY DRAWN BADGE IS THE DISC-CASE STICKER, sized by layout. A one-panel
// badge (HDR10 / HDR10+ / HLG, channels, Remux, WEB-DL / WEBRip / HDTV /
// CAM, DTS:X, codec words, a language's name, every cut but IMAX, HD, SD)
// is a near-black ground panel carrying the word at 0.62h semibold inside
// a true hairline: 0.05h in the badge ink at 70 % opacity (≈ 1.7pt at 34)
// - the frame present, never the loudest thing; box height = chip height
// h, radius 0.25h, side pad 0.26h. A two-panel badge (4K / 8K / 1080p, the
// "4K ULTRA HD" sticker - no free vector exists; it is typography below
// the originality threshold) is 1.75h tall, centred on the row, framed at
// 0.08h in full ink: an upper ground panel carrying the primary in the
// badge ink at 0.55 × box, `.black` weight, tight tracking, over a lower
// band 30 % of the box FILLED in full ink carrying the secondary in the
// ground colour, uppercase, wide tracking, flush to the frame's inner
// edge. The box is as wide as its widest line plus 2 × side pad - measured
// by layout, never estimated. Below `rail` the two panels hold while the
// band text stays ≥ 5pt (h ≥ 15.9), else the primary alone.
//
// EMPHASIS IS LIGHT, NEVER GEOMETRY: ghost (0.55 opacity), plain (the
// resting look), lit (a soft glow behind the chip in the badge ink,
// radius 0.25h at 45 %), vivid (a stronger glow, radius 0.45h at 70 %,
// with the ink at full brightness - white under `ink`, the gradient's
// highlight under `gold`). No capsule, no ring, no added shape at any
// level; marks, stickers, word badges and the flag glow the same way (the
// flag glows white). TONE: `ink` follows
// the axis's foreground; `brand` paints a mark its official hex - never a
// near-black official colour (black on dark is a missing logo, not a brand
// statement); `gold` is the metallic
// sticker and it is FOR THE DRAWN BADGES ONLY - frame, letters and band in
// the `Gold` gradient (flat `Gold.flat` below the rail), the ground
// `Gold.ground` - while brand marks stay in ink, white on dark, as disc
// cases print them beside gold stickers. Original-colour marks (the flag)
// ignore tone by construction. A TRAILING slot after an axis's
// last mark takes any view the consumer wants there.
//
// Two rungs, one threshold (`SpecChip.rail` = 32): at and above it lockups,
// below it the brand SYMBOLS (Dolby D, dts, the Blu-ray glyph, the flag);
// drawn badges are the same at both. A strip groups per axis: `.inkTight`
// within an axis, `.inkGap` between axes.

/// The form a mark takes: its symbol (the Dolby D, the Blu-ray glyph) or
/// its lockup (symbol and wordmark). The rail picks one; a consumer may
/// name the form outright - a poster corner wants symbols beside the
/// sticker at any height, a rail wants lockups.
public enum MarkForm: Sendable {
    case symbol
    case lockup
}

/// One mark's content: artwork from the catalog, a word that has none, or
/// the two-line disc-case badge.
public enum Glyph: Hashable, Sendable {
    case art(Mark)
    case word(String)
    case badge(primary: String, secondary: String)
}

extension Resolution {
    /// The disc-case sticker each resolution is drawn as: two panels for
    /// 4K, 8K and 1080p ("1080p" over "FULL HD"), one for HD (720p) and SD.
    public var glyph: Glyph {
        switch self {
        case .sd: .word("SD")
        case .p720: .word("HD")
        case .p1080: .badge(primary: "1080p", secondary: "FULL HD")
        case .p2160: .badge(primary: "4K", secondary: "ULTRA HD")
        case .p4320: .badge(primary: "8K", secondary: "ULTRA HD")
        }
    }
}

/// One glyph standing frameless, wearing its emphasis. Public so a
/// consumer with an axis this product does not name (a container, a frame
/// rate) can still render it in the family's grammar.
public struct SpecChip: View {
    /// The height at and above which a chip wears lockups; below it, symbols.
    public static let rail: CGFloat = 32
    /// The drawn badges' ground panel under `ink` and `brand` (gold has its
    /// own, `Gold.ground`).
    nonisolated(unsafe) public static var ground = Color(white: 0.07)

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
            .shadow(color: glow, radius: glowRadius)
            .accessibilityLabel(accessibility)
    }

    /// The glow behind a lit or vivid chip: the badge ink's own colour
    /// (white under `ink`, the flat gold under `gold`), never a shape.
    private var glow: Color {
        switch emphasis {
        case .ghost, .plain: .clear
        case .lit: glowInk.opacity(0.45)
        case .vivid: glowInk.opacity(0.7)
        }
    }

    private var glowRadius: CGFloat {
        switch emphasis {
        case .ghost, .plain: 0
        case .lit: height * 0.25
        case .vivid: height * 0.45
        }
    }

    private var glowInk: Color { tone == .gold ? Gold.flat : .white }

    @ViewBuilder
    private var content: some View {
        switch glyph {
        case .art(let m):
            // A file whose drawn box is smaller than its grid renders taller
            // so the BOX, not the grid, lands at the chip height. Template
            // images take any shape style, so gold is a gradient fill.
            m.image
                .resizable()
                .scaledToFit()
                .frame(height: height * m.boxScale)
                .foregroundStyle(markStyle(m))
                .accessibilityLabel(m.title)
                .frame(height: height)
        case .word(let w):
            sticker(box: height, band: nil) {
                Text(w)
                    .font(.system(size: height * 0.62, weight: .semibold))
                    .lineLimit(1)
            }
        case .badge(let primary, let secondary):
            let box = height * 1.75
            let bandText = box * 0.30 * 0.6
            if bandText >= 5 {
                sticker(box: box, band: secondary) {
                    Text(primary)
                        .font(.system(size: box * 0.55, weight: .black))
                        .tracking(-0.03 * box * 0.55)
                        .lineLimit(1)
                }
            } else {
                sticker(box: height, band: nil) {
                    Text(primary)
                        .font(.system(size: height * 0.62, weight: .black))
                        .tracking(-0.03 * height * 0.62)
                        .lineLimit(1)
                }
            }
        }
    }

    /// THE STICKER, sized by its content. A ground panel with the text;
    /// with `band`, the lower 30 % of the box is filled with the ink and
    /// carries the band text in the ground colour, flush to the frame's
    /// inner edge; both lines are `fixedSize` so the box is as wide as the
    /// wider one plus the side pad. The frame is a true hairline on a
    /// one-panel badge (0.05h, ink at 70 %) and 0.08h in full ink on the
    /// two-panel sticker. h is the CHIP height, so a taller sticker keeps
    /// the family's corner and side pad.
    private func sticker(box: CGFloat, band: String?, @ViewBuilder _ text: () -> some View)
        -> some View
    {
        let bandHeight = band == nil ? 0 : box * 0.30
        let radius = height * 0.25
        let frameWidth = band == nil ? height * 0.05 : height * 0.08
        let frameOpacity = band == nil ? 0.7 : 1.0
        return VStack(spacing: 0) {
            text()
                .fixedSize()
                .foregroundStyle(ink)
                .padding(.horizontal, height * 0.26)
                .frame(maxWidth: .infinity)
                .frame(height: box - bandHeight)
            if let band {
                Text(band.uppercased())
                    .font(.system(size: bandHeight * 0.6, weight: .semibold))
                    .tracking(0.14 * bandHeight * 0.6)
                    .fixedSize()
                    .foregroundStyle(ground)
                    .padding(.horizontal, height * 0.26)
                    .frame(maxWidth: .infinity)
                    .frame(height: bandHeight)
                    .background(ink)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: box)
        .background(ground)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(ink, lineWidth: frameWidth)
                .opacity(frameOpacity)
        }
    }

    private var accessibility: String {
        switch glyph {
        case .art(let m): m.title
        case .word(let w): w
        case .badge(let p, let s): "\(p) \(s)"
        }
    }

    /// The drawn badges' ink: gold's gradient at the rail, flat gold below
    /// it, else the primary ink; at full brightness when vivid (white, or
    /// the gradient's highlight stop).
    private var ink: AnyShapeStyle {
        let vivid = emphasis == .vivid
        guard tone == .gold else { return AnyShapeStyle(vivid ? Color.white : Color.primary) }
        if vivid { return AnyShapeStyle(Gold.stops.first?.color ?? Gold.flat) }
        // The metal is a gradient wherever the DRAWN BOX is at the rail or
        // above: the two-panel sticker stands 1.75 × the chip height, so it
        // earns the gradient below the rail while a one-line badge there
        // stays flat (a gradient at 8pt is noise).
        let box: CGFloat = if case .badge = glyph { height * 1.75 } else { height }
        return box >= SpecChip.rail ? AnyShapeStyle(Gold.gradient) : AnyShapeStyle(Gold.flat)
    }

    private var ground: Color { tone == .gold ? Gold.ground : SpecChip.ground }

    /// THE TONE RULE for marks. `ink` follows the axis. `brand` paints the
    /// mark its official hex, and never a near-black one (luminance under
    /// 0.15 - Dolby, HDR10, DVD): black on a dark ground is a missing logo.
    /// `gold` paints the mark in the same metal as the stickers beside it -
    /// one foil across the whole row, the way a premium case is stamped (a
    /// white mark beside a gold sticker read as two different objects).
    /// Vivid lifts ink to white. The flag renders as authored regardless.
    private func markStyle(_ m: Mark) -> AnyShapeStyle {
        if tone == .brand, m.luminance >= 0.15 { return AnyShapeStyle(m.color) }
        if tone == .gold { return ink }
        return AnyShapeStyle(emphasis == .vivid ? Color.white : Color.primary)
    }
}

/// The per-axis options every value chip and the strip share.
public struct ChipOptions {
    public var emphasis: Emphasis = .plain
    public var height: CGFloat = 34
    public var trailing: AnyView? = nil
    public var detail: String? = nil
    public var tone: Tone = .ink
    /// The marks' form when the consumer names it; nil = the rail's rule.
    public var form: MarkForm? = nil

    var atRail: Bool { height >= SpecChip.rail }
    /// The form the marks take: named outright (a poster corner wants
    /// symbols beside the sticker at any height), else lockups at and
    /// above the rail, symbols below it.
    var markForm: MarkForm { form ?? (atRail ? .lockup : .symbol) }
    func glyph(_ marks: Marks) -> Glyph? {
        (markForm == .lockup ? marks.lockup : marks.symbol).map(Glyph.art)
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
        height: CGFloat = 34, trailing: AnyView? = nil, detail: String? = nil, tone: Tone = .ink,
        form: MarkForm? = nil
    ) {
        self.resolution = resolution
        self.range = range
        self.options = ChipOptions(
            emphasis: emphasis, height: height, trailing: trailing, detail: detail, tone: tone,
            form: form)
    }

    public var body: some View {
        var glyphs: [Glyph] = []
        if let r = resolution { glyphs.append(options.glyph(r.marks) ?? r.glyph) }
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
        trailing: AnyView? = nil, detail: String? = nil, tone: Tone = .ink,
        form: MarkForm? = nil
    ) {
        self.audio = audio
        self.options = ChipOptions(
            emphasis: emphasis, height: height, trailing: trailing, detail: detail, tone: tone,
            form: form)
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
        // An unnamed carrier (a claim) draws nothing: the object mark is the
        // whole claim.
        if let codec = audio.codec {
            glyphs.append(
                objectDrawn
                    ? .word(codec.label)
                    : options.glyph(codec.marks) ?? .word(codec.label))
        }
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
        height: CGFloat = 34, trailing: AnyView? = nil, detail: String? = nil, tone: Tone = .ink,
        form: MarkForm? = nil
    ) {
        self.tier = tier
        self.resolution = resolution
        self.options = ChipOptions(
            emphasis: emphasis, height: height, trailing: trailing, detail: detail, tone: tone,
            form: form)
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
        trailing: AnyView? = nil, detail: String? = nil, tone: Tone = .ink,
        form: MarkForm? = nil
    ) {
        self.lang = lang
        self.label = label
        self.options = ChipOptions(
            emphasis: emphasis, height: height, trailing: trailing, detail: detail, tone: tone,
            form: form)
    }

    public var body: some View {
        let word = label ?? lang.label
        var glyphs: [Glyph] = []
        if let flag = options.glyph(lang.marks) {
            glyphs.append(flag)
            // The flag alone in symbol form; the name beside it where lockups go.
            if options.markForm == .lockup { glyphs.append(.word(word)) }
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
        detail: String? = nil, tone: Tone = .ink, form: MarkForm? = nil
    ) {
        self.cut = cut
        self.options = ChipOptions(
            emphasis: emphasis, height: height, trailing: trailing, detail: detail, tone: tone,
            form: form)
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
    let form: MarkForm?

    public init(
        spec: MediaSpec, emphasis: Emphasis = .plain, height: CGFloat = 34,
        adornments: [Kind: AnyView] = [:], langLabel: String? = nil, omit: Set<Kind> = [],
        spacing: CGFloat = .inkGap, tone: Tone = .ink, form: MarkForm? = nil
    ) {
        self.spec = spec
        self.emphasis = emphasis
        self.height = height
        self.adornments = adornments
        self.langLabel = langLabel
        self.omit = omit
        self.spacing = spacing
        self.tone = tone
        self.form = form
    }

    public var body: some View {
        HStack(spacing: spacing) {
            if !omit.contains(.picture), spec.resolution != nil || spec.range != nil {
                PictureChip(
                    resolution: spec.resolution, range: spec.range, emphasis: emphasis,
                    height: height, trailing: adornments[.picture], tone: tone, form: form)
            }
            if !omit.contains(.sound), let audio = spec.audio {
                SoundChip(
                    audio: audio, emphasis: emphasis, height: height,
                    trailing: adornments[.sound], tone: tone, form: form)
            }
            if !omit.contains(.tier), let tier = spec.tier {
                TierChip(
                    tier: tier, resolution: spec.resolution, emphasis: emphasis, height: height,
                    trailing: adornments[.tier], tone: tone, form: form)
            }
            if !omit.contains(.lang), let lang = spec.lang {
                LangChip(
                    lang: lang, label: langLabel, emphasis: emphasis, height: height,
                    trailing: adornments[.lang], tone: tone, form: form)
            }
            if !omit.contains(.cut), let cut = spec.cut {
                CutChip(
                    cut: cut, emphasis: emphasis, height: height, trailing: adornments[.cut],
                    tone: tone, form: form)
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
