import Foundation
import MediaSpec

// The vocabulary gate. Every literal below is ALSO pinned by the React
// `media-spec` item's own check; the two renderers share a wire and this
// is how a rename on either side fails a gate instead of drawing a wrong
// chip. Then the label rules, the lenient-decode law and the mark catalog
// against its manifest.

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
    vocabulary("emphasis", Emphasis.self, want: "ghost,plain,washed,ringed")
    vocabulary("kind", Kind.self, want: "picture,sound,tier,lang,cut")
    let cuts = Cut.known.map(\.rawValue).joined(separator: ",")
    print("cut: \(cuts)")
    if cuts != "theatrical,extended,directors,unrated,uncut,final,imax,remastered" {
        fail("cut vocabulary is `\(cuts)`")
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
    // A language names its variety when a generic name exists, else the
    // language of its subtag alone (never "European Spanish"), else the tag;
    // the region subtag is read off the tag.
    if Lang("es-ES").label != "Castilian" || Lang("es-419").label != "Latin American Spanish" {
        fail("the variety table")
    }
    let es = Locale.current.localizedString(forLanguageCode: "es") ?? ""
    if es.isEmpty || Lang("es").label != es || Lang("es-MX").label != es {
        fail("a tag without a variety name labels its language alone: \(Lang("es-MX").label)")
    }
    if Lang("es-MX").label.localizedCaseInsensitiveContains("mex")
        || Lang("es-ES").label.localizedCaseInsensitiveContains("european")
    {
        fail("a label must never carry the region")
    }
    if Lang("zz-QQ").label != "zz-QQ" { fail("an unknown tag is its own label") }
    if Lang("es-ES").region != "ES" || Lang("es").region != nil || Lang("es-419").region != nil {
        fail("Lang.region")
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

    // ---- the catalog IS the manifest: every artwork on disk is a Mark ----
    let catalog = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("MediaSpec/Resources/Marks.xcassets")
    let onDisk = ((try? FileManager.default.contentsOfDirectory(atPath: catalog.path)) ?? [])
        .filter { $0.hasSuffix(".imageset") }.map { String($0.dropLast(".imageset".count)) }
        .sorted()
    let generated = Mark.allCases.map(\.rawValue).sorted()
    print("marks: \(generated.joined(separator: ","))")
    if onDisk != generated {
        fail("catalog \(onDisk) and Mark \(generated) disagree - run brandgen sync")
    }
    let wantMarks = [
        "badge4k", "badge8k", "badgehd", "badgesd",
        "bluray", "blurayglyph", "dolby", "dolbyatmos", "dolbydigital", "dolbydigitalplus",
        "dolbytruehd", "dolbyvision", "dts", "dtshdma", "dtswordmark", "dvd", "flac", "flages",
        "hdr10", "hdr10plus", "imax", "opus", "ultrahd", "ultrahdbluray",
    ]
    if generated != wantMarks { fail("the mark catalog drifted from its manifest") }
    for m in Mark.allCases where m.aspect <= 0 { fail("\(m.rawValue) has no aspect") }
    if Mark.flages.original == false { fail("the flag keeps its own colours") }
    if Mark.dolby.original { fail("a logo is template-rendered") }
    if Mark.dolby.aspect != 1 || Mark.dts.aspect != 1 { fail("simple-icons symbols are square") }
    if Mark.badge4k.aspect != 1 || Mark.badge4k.original {
        fail("the tabler badges are square templates")
    }
    // The value → mark binding, the manifest's own table. Resolutions are
    // drawn disc-case badges and bind no artwork; HDR10 and HDR10+ are
    // drawn too.
    if Resolution.allCases.contains(where: { $0.marks != .none })
        || Resolution.p2160.glyph != .badge(primary: "4K", secondary: "ULTRA HD")
        || Resolution.p4320.glyph != .badge(primary: "8K", secondary: "ULTRA HD")
        || Resolution.p1080.glyph != .word("FULL HD") || Resolution.p720.glyph != .word("HD")
        || Resolution.sd.glyph != .word("SD")
    {
        fail("resolution badges")
    }
    if DynamicRange.dolbyVision.marks != Marks(symbol: .dolby, lockup: .dolbyvision)
        || DynamicRange.hdr10Plus.marks != .none || DynamicRange.hdr10.marks != .none
        || DynamicRange.sdr.marks != .none || DynamicRange.hlg.marks != .none
        || Mark.badge4k.boxScale != 24.0 / 14.0 || Mark.dolby.boxScale != 1
        || ObjectAudio.atmos.marks != Marks(symbol: .dolby, lockup: .dolbyatmos)
        || ObjectAudio.dtsX.marks != .none
        || AudioCodec.trueHD.marks != Marks(symbol: .dolby, lockup: .dolbytruehd)
        || AudioCodec.dtsHDMA.marks != Marks(symbol: .dts, lockup: .dtshdma)
        || AudioCodec.aac.marks != .none
        || Tier.remux.marks(at: .p2160) != Marks(symbol: .blurayglyph, lockup: .ultrahdbluray)
        || Tier.bluray.marks(at: .p1080) != Marks(symbol: .blurayglyph, lockup: .bluray)
        || Tier.webdl.marks(at: .p2160) != .none
        || Lang("es-ES").marks != Marks(symbol: .flages, lockup: .flages)
        || Lang("es-419").marks != .none || Lang("es").marks != .none
        || Cut.imax.marks != Marks(symbol: .imax, lockup: .imax) || Cut.extended.marks != .none
    {
        fail("value → mark binding drifted from the manifest")
    }

    print("mediaspec-example check OK")
    exit(0)
}
