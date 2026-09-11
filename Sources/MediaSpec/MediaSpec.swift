import Foundation

// The MEDIA FORMAT vocabulary, typed: picture, sound, source tier,
// language and cut as values, the way Scores knows what IMDb is. An app
// passes VALUES, never label strings; this product owns every label, short
// form and mark. It is generic media visuals only: a consumer that needs
// MEANING - what a value's certainty is, how two values compare, a house
// spelling for a language - maps it in its own code onto `Emphasis`, a
// trailing slot, or a label override.
//
// The raw values are the WIRE spellings. A React `media-spec` item renders
// the same vocabulary with the identical literals; `mediaspec-example
// --check` pins them here, its own check pins them there, and a rename on
// either side fails a gate instead of drawing a wrong chip.

public enum Resolution: String, Codable, CaseIterable, Sendable, Hashable {
    case sd
    case p720 = "720p"
    case p1080 = "1080p"
    case p2160 = "2160p"
    case p4320 = "4320p"

    public var label: String {
        switch self {
        case .sd: "SD"
        case .p720: "720p"
        case .p1080: "1080p"
        case .p2160: "4K"
        case .p4320: "8K"
        }
    }
}

public enum DynamicRange: String, Codable, CaseIterable, Sendable, Hashable {
    case sdr
    case hlg
    case hdr10
    case hdr10Plus = "hdr10-plus"
    case dolbyVision = "dolby-vision"

    public var label: String {
        switch self {
        case .sdr: "SDR"
        case .hlg: "HLG"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .dolbyVision: "Dolby Vision"
        }
    }

    public var short: String {
        switch self {
        case .dolbyVision: "DV"
        default: label
        }
    }
}

public enum AudioCodec: String, Codable, CaseIterable, Sendable, Hashable {
    case aac
    case ac3
    case eac3
    case dts
    case dtsHDHRA = "dts-hd-hra"
    case dtsHDMA = "dts-hd-ma"
    case trueHD = "truehd"
    case flac
    case pcm
    case alac
    case opus
    case mp3
    case mp2
    case vorbis

    public var label: String {
        switch self {
        case .aac: "AAC"
        case .ac3: "DD"
        case .eac3: "DD+"
        case .dts: "DTS"
        case .dtsHDHRA: "DTS-HD HRA"
        case .dtsHDMA: "DTS-HD MA"
        case .trueHD: "TrueHD"
        case .flac: "FLAC"
        case .pcm: "PCM"
        case .alac: "ALAC"
        case .opus: "Opus"
        case .mp3: "MP3"
        case .mp2: "MP2"
        case .vorbis: "Vorbis"
        }
    }

    /// Bit-exact to the master. A fact of the codec, never of the bitrate.
    public var isLossless: Bool {
        switch self {
        case .trueHD, .dtsHDMA, .flac, .pcm, .alac: true
        default: false
        }
    }
}

public enum Channels: String, Codable, CaseIterable, Sendable, Hashable {
    case mono = "1.0"
    case stereo = "2.0"
    case surround51 = "5.1"
    case surround61 = "6.1"
    case surround71 = "7.1"

    public var label: String { rawValue }
}

/// Object audio rides ON a codec (TrueHD + Atmos, DD+ + Atmos, DTS-HD MA +
/// DTS:X); it is never a codec of its own.
public enum ObjectAudio: String, Codable, CaseIterable, Sendable, Hashable {
    case atmos
    case dtsX = "dts-x"

    public var label: String {
        switch self {
        case .atmos: "Atmos"
        case .dtsX: "DTS:X"
        }
    }
}

/// The SOURCE tier - where the bits came from - as its own axis beside
/// picture and sound.
public enum Tier: String, Codable, CaseIterable, Sendable, Hashable {
    case remux
    case bluray
    case webdl
    case webrip
    case hdtv
    case dvd
    case cam

    public var label: String {
        switch self {
        case .remux: "Remux"
        case .bluray: "Blu-ray"
        case .webdl: "WEB-DL"
        case .webrip: "WEBRip"
        case .hdtv: "HDTV"
        case .dvd: "DVD"
        case .cam: "CAM"
        }
    }
}

/// A BCP-47 tag. Its label is the system's display name for the tag in
/// the current locale, region-aware ("Spanish (Spain)"), falling back to
/// the tag itself; a consumer with its own spelling passes `label:` to
/// `LangChip`.
public struct Lang: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ tag: String) { self.rawValue = tag }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public var label: String {
        let id = rawValue.replacingOccurrences(of: "-", with: "_")
        if let name = Locale.current.localizedString(forIdentifier: id), !name.isEmpty {
            return name
        }
        return rawValue
    }

    /// The region subtag (ISO 3166-1 alpha-2), when the tag carries one.
    public var region: String? {
        let parts = rawValue.split(separator: "-")
        guard parts.count >= 2 else { return nil }
        let r = parts[1]
        return r.count == 2 && r.allSatisfy(\.isLetter) ? r.uppercased() : nil
    }
}

/// The release cut. Known cuts carry a house label; anything else renders
/// verbatim, because a cut is whatever the disc's spine says it is.
public enum Cut: Codable, Hashable, Sendable {
    case theatrical
    case extended
    case directors
    case unrated
    case uncut
    case final
    case imax
    case remastered
    case other(String)

    /// The known cases in declaration order - `.other` carries no raw value
    /// of its own, so `CaseIterable` would lie; this is the pinned list.
    public static let known: [Cut] = [
        .theatrical, .extended, .directors, .unrated, .uncut, .final, .imax, .remastered,
    ]

    public var rawValue: String {
        switch self {
        case .theatrical: "theatrical"
        case .extended: "extended"
        case .directors: "directors"
        case .unrated: "unrated"
        case .uncut: "uncut"
        case .final: "final"
        case .imax: "imax"
        case .remastered: "remastered"
        case .other(let s): s
        }
    }

    public init(rawValue: String) {
        self = Cut.known.first { $0.rawValue == rawValue } ?? .other(rawValue)
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public var label: String {
        switch self {
        case .theatrical: "theatrical"
        case .extended: "extended"
        case .directors: "director's cut"
        case .unrated: "unrated"
        case .uncut: "uncut"
        case .final: "final cut"
        case .imax: "IMAX"
        case .remastered: "remastered"
        case .other(let s): s
        }
    }
}

/// How much a chip stands out, named for the look alone: `ghost` is the
/// mark at 0.55 opacity; `plain` is full ink on no ground; `washed` is full
/// ink over a soft `inkRest` capsule; `ringed` is the wash plus an
/// `inkEdge` ring. What any of it means is the consumer's mapping.
public enum Emphasis: String, Codable, CaseIterable, Sendable, Hashable {
    case ghost
    case plain
    case washed
    case ringed
}

/// The five axes a spec renders, in the order a strip composes them.
public enum Kind: String, Codable, CaseIterable, Sendable, Hashable {
    case picture
    case sound
    case tier
    case lang
    case cut

    public var symbol: String {
        switch self {
        case .picture: "tv"
        case .sound: "speaker.wave.2"
        case .tier: "opticaldisc"
        case .lang: "character.bubble"
        case .cut: "scissors"
        }
    }
}

// MARK: - Lenient decoding

/// THE VOCABULARY BOUNDARY LAW: an unknown raw value decodes the field to
/// nil, never throws, never logs. A wire that grows a word this build does
/// not know must blank one chip, not the whole row - applied at the enum
/// instead of at every consumer.
@propertyWrapper
public struct Lenient<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var wrappedValue: Value?

    public init(wrappedValue: Value?) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        wrappedValue = try? decoder.singleValueContainer().decode(Value.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let wrappedValue { try c.encode(wrappedValue) } else { try c.encodeNil() }
    }
}

extension KeyedDecodingContainer {
    /// A missing key is the same absence as an unknown value.
    public func decode<V>(_: Lenient<V>.Type, forKey key: Key) throws -> Lenient<V> {
        try decodeIfPresent(Lenient<V>.self, forKey: key) ?? Lenient(wrappedValue: nil)
    }
}

/// One audio track's format. `codec` is the one required fact: a track
/// whose codec is foreign to this build is no track at all.
public struct Audio: Codable, Hashable, Sendable {
    public var codec: AudioCodec
    @Lenient public var channels: Channels?
    @Lenient public var object: ObjectAudio?

    public init(codec: AudioCodec, channels: Channels? = nil, object: ObjectAudio? = nil) {
        self.codec = codec
        self.channels = channels
        self.object = object
    }
}

/// A media spec: every axis optional, because a wire carries whatever
/// subset it knows.
public struct MediaSpec: Codable, Hashable, Sendable {
    @Lenient public var resolution: Resolution?
    @Lenient public var range: DynamicRange?
    @Lenient public var audio: Audio?
    @Lenient public var tier: Tier?
    @Lenient public var lang: Lang?
    @Lenient public var cut: Cut?

    public init(
        resolution: Resolution? = nil, range: DynamicRange? = nil, audio: Audio? = nil,
        tier: Tier? = nil, lang: Lang? = nil, cut: Cut? = nil
    ) {
        self.resolution = resolution
        self.range = range
        self.audio = audio
        self.tier = tier
        self.lang = lang
        self.cut = cut
    }
}

// MARK: - Labels (pure, the one spelling every chip and every test reads)

/// "4K · Dolby Vision" / "4K·DV"; SDR is the unmarked case and is omitted
/// ("1080p", "4K"). A range with no resolution renders the range alone.
public func pictureLabel(_ resolution: Resolution?, _ range: DynamicRange?, short: Bool = false)
    -> String
{
    let res = resolution?.label
    let rng: String? =
        switch range {
        case nil, .sdr?: nil
        case let r?: short ? r.short : r.label
        }
    switch (res, rng) {
    case (let r?, let g?): return short ? "\(r)·\(g)" : "\(r) · \(g)"
    case (let r?, nil): return r
    case (nil, let g?): return g
    case (nil, nil): return ""
    }
}

/// "TrueHD Atmos 7.1", "DD+ Atmos 5.1", "DTS-HD MA 5.1", "AAC 2.0"; short
/// is the object format when present, else the codec.
public func soundLabel(_ audio: Audio, short: Bool = false) -> String {
    if short { return audio.object?.label ?? audio.codec.label }
    var parts = [audio.codec.label]
    if let o = audio.object { parts.append(o.label) }
    if let c = audio.channels { parts.append(c.label) }
    return parts.joined(separator: " ")
}
