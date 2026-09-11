import Foundation
import MediaSpec

// The vocabulary gate. Every literal below is ALSO pinned by the React
// `media-spec` item's own check; the two renderers share a wire and this
// is how a rename on either side fails a gate instead of drawing a wrong
// chip. Then the label rules, the provenance order, the lenient-decode law
// and the zero-resource law.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("mediaspec-example check FAILED: " + message + "\n").utf8))
    exit(1)
}

func vocabulary<T: CaseIterable & RawRepresentable>(_ name: String, _: T.Type, want: String)
where T.RawValue == String {
    let got = T.allCases.map(\.rawValue).joined(separator: ",")
    print("\(name): \(got)")
    if got != want { fail("\(name) vocabulary is `\(got)`, the pinned literal is `\(want)`") }
}

func runChecks() -> Never {
    // ---- the shared literals, one line per enum, declaration order ----
    vocabulary("resolution", Resolution.self, want: "sd,720p,1080p,2160p,4320p")
    vocabulary("range", DynamicRange.self, want: "sdr,hlg,hdr10,hdr10-plus,dolby-vision")
    vocabulary(
        "audio-codec", AudioCodec.self,
        want: "aac,ac3,eac3,dts,dts-hd-hra,dts-hd-ma,truehd,flac,pcm,alac,opus,mp3,mp2,vorbis")
    vocabulary("channels", Channels.self, want: "1.0,2.0,5.1,6.1,7.1")
    vocabulary("object-audio", ObjectAudio.self, want: "atmos,dts-x")
    vocabulary("tier", Tier.self, want: "remux,bluray,webdl,webrip,hdtv,dvd,cam")
    vocabulary("provenance", Provenance.self, want: "claim,verified,measured,delivered")
    vocabulary("delta", Delta.self, want: "better,same,worse")
    vocabulary("kind", Kind.self, want: "picture,sound,tier,lang,cut")
    let cuts = Cut.known.map(\.rawValue).joined(separator: ",")
    print("cut: \(cuts)")
    if cuts != "theatrical,extended,directors,unrated,uncut,final,imax,remastered" {
        fail("cut vocabulary is `\(cuts)`")
    }

    // ---- provenance is ordered by certainty ----
    if !(Provenance.claim < .verified && .verified < .measured && .measured < .delivered) {
        fail("provenance must ascend claim < verified < measured < delivered")
    }
    if Provenance.allCases.sorted() != Provenance.allCases {
        fail("provenance declaration order must be its sort order")
    }

    // ---- lossless is a fact of the codec ----
    for c in AudioCodec.allCases {
        let want = [.trueHD, .dtsHDMA, .flac, .pcm, .alac].contains(c)
        if c.isLossless != want { fail("\(c.rawValue).isLossless should be \(want)") }
    }

    // ---- the label rules ----
    let picture: [(Resolution?, DynamicRange?, String, String)] = [
        (.p2160, .dolbyVision, "4K · Dolby Vision", "4K·DV"),
        (.p2160, .hdr10Plus, "4K · HDR10+", "4K·HDR10+"),
        (.p2160, .sdr, "4K", "4K"),
        (.p1080, nil, "1080p", "1080p"),
        (.p1080, .dolbyVision, "1080p · Dolby Vision", "1080p·DV"),
        (.sd, .sdr, "SD", "SD"),
        (nil, .hlg, "HLG", "HLG"),
        (nil, nil, "", ""),
    ]
    for (r, g, long, short) in picture {
        if pictureLabel(r, g) != long {
            fail(
                "pictureLabel(\(String(describing: r)), \(String(describing: g))) = `\(pictureLabel(r, g))`, want `\(long)`"
            )
        }
        if pictureLabel(r, g, short: true) != short {
            fail("pictureLabel short = `\(pictureLabel(r, g, short: true))`, want `\(short)`")
        }
    }
    let sound: [(Audio, String, String)] = [
        (Audio(codec: .trueHD, channels: .surround71, object: .atmos), "TrueHD Atmos 7.1", "Atmos"),
        (Audio(codec: .eac3, channels: .surround51, object: .atmos), "DD+ Atmos 5.1", "Atmos"),
        (Audio(codec: .dtsHDMA, channels: .surround51), "DTS-HD MA 5.1", "DTS-HD MA"),
        (Audio(codec: .aac, channels: .stereo), "AAC 2.0", "AAC"),
        (
            Audio(codec: .dtsHDMA, channels: .surround71, object: .dtsX), "DTS-HD MA DTS:X 7.1",
            "DTS:X"
        ),
        (Audio(codec: .flac), "FLAC", "FLAC"),
    ]
    for (a, long, short) in sound {
        if soundLabel(a) != long { fail("soundLabel = `\(soundLabel(a))`, want `\(long)`") }
        if soundLabel(a, short: true) != short {
            fail("soundLabel short = `\(soundLabel(a, short: true))`, want `\(short)`")
        }
    }
    if Lang("es-ES").label != "castellano" || Lang("es-419").label != "latino"
        || Lang("fr-FR").label != "fr-FR"
    {
        fail("Lang labels")
    }
    if Cut(rawValue: "directors").label != "director's cut"
        || Cut(rawValue: "fan edit").label != "fan edit"
    {
        fail("Cut labels")
    }
    if Cut(rawValue: "fan edit") != .other("fan edit") {
        fail("an unknown cut is .other, verbatim")
    }

    // ---- the lenient-decode law: a foreign word blanks one field ----
    let wire =
        #"{"resolution":"2160p","range":"nonsense","audio":{"codec":"truehd","object":"atmos","channels":"7.1"},"tier":"laserdisc","cut":"fan edit"}"#
    let spec: MediaSpec
    do {
        spec = try JSONDecoder().decode(MediaSpec.self, from: Data(wire.utf8))
    } catch {
        fail("lenient decode threw: \(error)")
    }
    if spec.resolution != .p2160 { fail("resolution should survive a foreign sibling") }
    if spec.range != nil {
        fail("a foreign range must decode to nil, got \(String(describing: spec.range))")
    }
    if spec.tier != nil { fail("a foreign tier must decode to nil") }
    if spec.audio != Audio(codec: .trueHD, channels: .surround71, object: .atmos) {
        fail("audio must arrive intact: \(String(describing: spec.audio))")
    }
    if spec.cut != .other("fan edit") { fail("an unknown cut is carried verbatim, never dropped") }
    let bare = try? JSONDecoder().decode(MediaSpec.self, from: Data("{}".utf8))
    if bare == nil || bare! != MediaSpec() { fail("an empty object is an empty spec") }
    // A foreign codec is a foreign TRACK: the audio field blanks, nothing throws.
    let foreignCodec = try? JSONDecoder().decode(
        MediaSpec.self, from: Data(#"{"audio":{"codec":"mqa"}}"#.utf8))
    if foreignCodec == nil || foreignCodec!.audio != nil {
        fail("a foreign codec must blank the audio")
    }
    // Round trip keeps the words.
    let again = try? JSONDecoder().decode(MediaSpec.self, from: JSONEncoder().encode(spec))
    if again != spec { fail("encode/decode round trip drifted") }

    // ---- zero brand bytes, by construction ----
    let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("MediaSpec/Resources")
    if FileManager.default.fileExists(atPath: resources.path) {
        fail(
            "MediaSpec must ship no resources (Dolby/DTS are licensed marks; words at 10 ft beat logos)"
        )
    }

    print("mediaspec-example check OK")
    exit(0)
}
