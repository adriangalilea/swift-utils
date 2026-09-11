import Ink
import MediaSpec
import SwiftUI

// The windowed half: every chip variant on black, the visual sweep a
// person judges (never a PNG). One variable per section - the sweep
// proves a treatment reads across the whole vocabulary, never that three
// hand-picked chips look nice together. The recipes at the end show what
// the generic ergonomics allow, in abstract terms.

struct DemoApp: App {
    var body: some Scene {
        WindowGroup("mediaspec-example") {
            ScrollView {
                DemoView().padding(.inkBlock)
            }
            .background(Color.black)
            .frame(minWidth: 1400, minHeight: 800)
        }
    }
}

struct DemoView: View {
    let reference = MediaSpec(
        resolution: .p2160, range: .dolbyVision,
        audio: Audio(codec: .trueHD, channels: .surround71, object: .atmos),
        tier: .remux, lang: Lang("es-ES"), cut: .extended)

    var body: some View {
        VStack(alignment: .leading, spacing: .inkBlock) {
            section("picture · every resolution × every range") {
                ForEach(DynamicRange.allCases, id: \.self) { range in
                    HStack(spacing: .inkGap) {
                        ForEach(Resolution.allCases, id: \.self) { res in
                            PictureChip(resolution: res, range: range)
                        }
                    }
                }
            }
            section("sound · codecs, channels, object audio") {
                HStack(spacing: .inkGap) {
                    SoundChip(audio: Audio(codec: .trueHD, channels: .surround71, object: .atmos))
                    SoundChip(audio: Audio(codec: .eac3, channels: .surround51, object: .atmos))
                    SoundChip(audio: Audio(codec: .dtsHDMA, channels: .surround71, object: .dtsX))
                    SoundChip(audio: Audio(codec: .dtsHDMA, channels: .surround51))
                    SoundChip(audio: Audio(codec: .dts, channels: .surround51))
                    SoundChip(audio: Audio(codec: .ac3, channels: .surround51))
                    SoundChip(audio: Audio(codec: .aac, channels: .stereo))
                    SoundChip(audio: Audio(codec: .flac, channels: .stereo))
                }
            }
            section("tier · lang · cut") {
                HStack(spacing: .inkGap) {
                    ForEach(Tier.allCases, id: \.self) { TierChip(tier: $0, resolution: .p2160) }
                }
                HStack(spacing: .inkGap) {
                    ForEach(Tier.allCases, id: \.self) { TierChip(tier: $0, resolution: .p1080) }
                }
                HStack(spacing: .inkGap) {
                    ForEach(["es-ES", "es-419", "es-MX", "en", "fr-CA", "ja"], id: \.self) {
                        LangChip(lang: Lang($0))
                    }
                }
                HStack(spacing: .inkGap) {
                    ForEach(Cut.known, id: \.self) { CutChip(cut: $0) }
                    CutChip(cut: .other("fan edit"))
                }
            }
            section("emphasis · one strip, four looks") {
                ForEach(Emphasis.allCases, id: \.self) { e in
                    HStack(spacing: .inkGap) {
                        Text(e.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        MediaSpecStrip(spec: reference, emphasis: e)
                    }
                }
            }
            section("height · 24 / 34 / 44") {
                ForEach([24, 34, 44] as [CGFloat], id: \.self) { h in
                    MediaSpecStrip(spec: reference, height: h)
                }
            }
            section("detail · the quiet second line") {
                HStack(spacing: .inkGap) {
                    PictureChip(
                        resolution: .p2160, range: .hdr10, emphasis: .ringed, height: 44,
                        detail: "source says more than this")
                    SoundChip(
                        audio: Audio(codec: .aac, channels: .surround51), emphasis: .ringed,
                        height: 44, detail: "re-encoded")
                }
            }
            section("trailing · any view after an axis's last mark") {
                MediaSpecStrip(
                    spec: MediaSpec(
                        resolution: .p2160, range: .hdr10,
                        audio: Audio(codec: .dtsHDMA, channels: .surround51), tier: .webdl,
                        lang: Lang("es-ES")),
                    emphasis: .ghost,
                    adornments: [
                        .picture: AnyView(Text("▼").foregroundStyle(.secondary)),
                        .sound: AnyView(Text("=").foregroundStyle(.secondary)),
                        .tier: AnyView(Text("▼").foregroundStyle(.secondary)),
                        .lang: AnyView(Image(systemName: "star.fill").foregroundStyle(.yellow)),
                    ])
            }
            section("omit · a surface that states an axis elsewhere") {
                MediaSpecStrip(spec: reference, omit: [.tier, .cut])
            }
            section("rungs · symbols (24) vs lockups (34, 44), ink vs brand") {
                ForEach([24, 34, 44] as [CGFloat], id: \.self) { h in
                    ForEach(Tone.allCases, id: \.self) { tone in
                        HStack(spacing: .inkGap) {
                            Text("\(Int(h)) \(tone.rawValue)").font(.caption.monospaced())
                                .foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                            MediaSpecStrip(
                                spec: MediaSpec(
                                    resolution: .p2160, range: .dolbyVision,
                                    audio: Audio(
                                        codec: .trueHD, channels: .surround71, object: .atmos),
                                    tier: .remux, lang: Lang("es-ES"), cut: .imax),
                                height: h, tone: tone)
                            MediaSpecStrip(
                                spec: MediaSpec(
                                    resolution: .p2160, range: .hdr10Plus,
                                    audio: Audio(
                                        codec: .dtsHDMA, channels: .surround71, object: .dtsX),
                                    tier: .bluray),
                                height: h, tone: tone)
                        }
                    }
                }
            }
            section(
                "badges · the one drawn geometry beside the tabler artwork (both wired), then the retired Commons badges"
            ) {
                ForEach([24, 34, 44] as [CGFloat], id: \.self) { h in
                    HStack(spacing: .inkTight) {
                        ForEach(
                            ["720p", "HDR10", "HDR10+", "HLG", "7.1", "Remux", "WEB-DL", "DTS:X"],
                            id: \.self
                        ) { SpecChip($0, height: h) }
                        SpecChip(.art(.badgesd), height: h)
                        SpecChip(.art(.badgehd), height: h)
                        SpecChip(.art(.badge4k), height: h)
                        SpecChip(.art(.badge8k), height: h)
                        Text("·").foregroundStyle(.tertiary)
                        SpecChip(.art(.hdr10), height: h)
                        SpecChip(.art(.hdr10plus), height: h)
                    }
                }
            }
            section("marks · the catalog at 24 / 34 / 44, ink then brand, then the four looks") {
                ForEach(Mark.allCases, id: \.self) { m in
                    HStack(spacing: .inkLane) {
                        Text(m.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        ForEach([24, 34, 44] as [CGFloat], id: \.self) { h in
                            SpecChip(.art(m), height: h)
                        }
                        SpecChip(.art(m), height: 34, tone: .brand)
                        ForEach(Emphasis.allCases, id: \.self) { e in
                            SpecChip(.art(m), emphasis: e, height: 28)
                        }
                        Text(String(format: "%.2f · lum %.2f", m.aspect, m.luminance))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            recipes
        }
    }

    // ---- recipes: what the generic ergonomics allow, in abstract terms ----

    /// A consumer's own scale of certainty, mapped onto the four looks.
    let emphasisFor: [(String, Emphasis)] = [
        ("rumoured", .ghost), ("stated", .plain), ("checked", .washed), ("playing", .ringed),
    ]

    var recipes: some View {
        VStack(alignment: .leading, spacing: .inkBlock) {
            section("recipe · a scale of certainty — the ladder is yours to name") {
                ForEach(emphasisFor, id: \.0) { step, e in
                    HStack(spacing: .inkGap) {
                        Text(step).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        MediaSpecStrip(spec: reference, emphasis: e)
                    }
                }
            }
            section("recipe · comparing against what you have — the slot takes anything") {
                let mine = MediaSpec(
                    resolution: .p1080, range: .sdr,
                    audio: Audio(codec: .dtsHDMA, channels: .surround51), tier: .bluray)
                let theirs = reference
                let verdict: (Int) -> AnyView = { d in
                    AnyView(
                        Text(d > 0 ? "▲" : d < 0 ? "▼" : "=")
                            .foregroundStyle(d > 0 ? .green : d < 0 ? .red : .secondary))
                }
                let picture =
                    (theirs.resolution == .p2160 ? 1 : 0) - (mine.resolution == .p2160 ? 1 : 0)
                let sound =
                    (theirs.audio?.object != nil ? 1 : 0) - (mine.audio?.object != nil ? 1 : 0)
                let tier = (theirs.tier == .remux ? 1 : 0) - (mine.tier == .remux ? 1 : 0)
                MediaSpecStrip(spec: mine)
                MediaSpecStrip(
                    spec: theirs, emphasis: .ghost,
                    adornments: [
                        .picture: verdict(picture), .sound: verdict(sound), .tier: verdict(tier),
                        .cut: AnyView(
                            Text("+41.2 GB").font(.caption.monospaced()).foregroundStyle(.secondary)
                        ),
                    ])
            }
            section("recipe · your own words — a label override per tag") {
                HStack(spacing: .inkGap) {
                    LangChip(lang: Lang("fr-CA"), label: "Québécois")
                    LangChip(lang: Lang("de-CH"), label: "Swiss German")
                    LangChip(lang: Lang("pt-BR"), label: "Brazilian")
                    LangChip(lang: Lang("es-ES"), label: "Peninsular")
                }
            }
            section("recipe · a poster corner — the small rung, two marks, a scrim") {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.25), Color(white: 0.08)], startPoint: .top,
                                endPoint: .bottom)
                        )
                        .frame(width: 160, height: 240)
                    MediaSpecStrip(
                        spec: MediaSpec(
                            resolution: .p2160, range: .dolbyVision,
                            audio: Audio(codec: .trueHD, channels: .surround71, object: .atmos)),
                        height: 20, omit: [.tier, .lang, .cut], spacing: .inkTight
                    )
                    .padding(6)
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: .inkGap) {
            Text(title).planeHeaderStyle()
            content()
        }
    }
}
