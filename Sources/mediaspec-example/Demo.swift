import Ink
import MediaSpec
import SwiftUI

// The windowed half: every chip variant on black, the operator's visual
// sweep. One variable per section - the sweep proves a treatment reads
// across the whole vocabulary, never that three hand-picked chips look
// nice together.

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
                    ForEach(Tier.allCases, id: \.self) { TierChip(tier: $0) }
                }
                HStack(spacing: .inkGap) {
                    LangChip(lang: Lang("es-ES"))
                    LangChip(lang: Lang("es-419"))
                    LangChip(lang: Lang("en"))
                    LangChip(lang: Lang("ja"))
                }
                HStack(spacing: .inkGap) {
                    ForEach(Cut.known, id: \.self) { CutChip(cut: $0) }
                    CutChip(cut: .other("fan edit"))
                }
            }
            section("provenance · one strip, four weights") {
                ForEach(Provenance.allCases, id: \.self) { p in
                    HStack(spacing: .inkGap) {
                        Text(p.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        MediaSpecStrip(spec: reference, provenance: p)
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
                        resolution: .p2160, range: .hdr10, provenance: .delivered, height: 44,
                        detail: "Dolby Vision source · HDR10 here")
                    SoundChip(
                        audio: Audio(codec: .aac, channels: .surround51), provenance: .delivered,
                        height: 44, detail: "TrueHD Atmos source · AAC here")
                    LangChip(
                        lang: Lang("es-ES"), provenance: .claim, height: 44,
                        detail: "the name says so")
                }
            }
            section("delta · a candidate against the owned copy") {
                MediaSpecStrip(
                    spec: MediaSpec(
                        resolution: .p2160, range: .hdr10,
                        audio: Audio(codec: .dtsHDMA, channels: .surround51), tier: .webdl,
                        lang: Lang("es-ES")),
                    provenance: .claim,
                    deltas: [.picture: .worse, .sound: .same, .tier: .worse, .lang: .better])
                MediaSpecStrip(
                    spec: MediaSpec(
                        resolution: .p2160, range: .dolbyVision,
                        audio: Audio(codec: .trueHD, channels: .surround71, object: .atmos),
                        tier: .remux),
                    provenance: .claim,
                    deltas: [.picture: .better, .sound: .better, .tier: .same])
            }
            section("omit · a surface that states an axis elsewhere") {
                MediaSpecStrip(spec: reference, omit: [.tier, .cut])
            }
            section("rungs · the poster symbols (24) vs the rail lockups (34, 44), ink vs brand") {
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
            section("badges · artwork badges beside drawn word-badges, same geometry") {
                ForEach([24, 34, 44] as [CGFloat], id: \.self) { h in
                    HStack(spacing: .inkTight) {
                        SpecChip(.art(.badgesd), height: h)
                        SpecChip(.art(.badgehd), height: h)
                        SpecChip(.art(.badge4k), height: h)
                        SpecChip(.art(.badge8k), height: h)
                        SpecChip(.art(.hdr10), height: h)
                        SpecChip(.art(.hdr10plus), height: h)
                        SpecChip("720p", height: h)
                        SpecChip("HLG", height: h)
                        SpecChip("7.1", height: h)
                        SpecChip("Remux", height: h)
                        SpecChip("WEB-DL", height: h)
                        SpecChip("DTS:X", height: h)
                        SpecChip("castellano", height: h)
                    }
                }
            }
            section("marks · the catalog at 24 / 34 / 44, ink then brand, then the four weights") {
                ForEach(Mark.allCases, id: \.self) { m in
                    HStack(spacing: .inkLane) {
                        Text(m.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        ForEach([24, 34, 44] as [CGFloat], id: \.self) { h in
                            SpecChip(.art(m), height: h)
                        }
                        SpecChip(.art(m), height: 34, tone: .brand)
                        ForEach(Provenance.allCases, id: \.self) { p in
                            SpecChip(.art(m), provenance: p, height: 28)
                        }
                        Text(String(format: "%.2f · lum %.2f", m.aspect, m.luminance))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
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
