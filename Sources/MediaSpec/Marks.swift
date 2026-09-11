import SwiftUI

// WHICH MARK A VALUE WEARS. `Mark` (generated) is the catalog of artworks;
// this file is the one place a vocabulary value is bound to a symbol (the
// poster rung: a disc-sized glyph) and a lockup (the rail rung: the full
// logotype, run inline with the text). A value with no entry renders as
// words, exactly as before the catalog existed.
//
// The manifest rule: a mark REPLACES the word it stands for, the rest of
// the label stays text. "4K" + the Dolby Vision lockup; the Dolby Atmos
// lockup + "TrueHD 7.1"; the Blu-ray lockup + "Remux". DTS:X has no
// artwork anywhere - it is the dts wordmark + ":X" set in the chip's type.

/// How a mark is coloured. `ink` follows the chip's foreground (one ink,
/// the flare rule); `brand` uses the mark's official hex. A mark with
/// intrinsic colours (the flag) ignores tone by construction.
public enum Tone: String, Codable, CaseIterable, Sendable, Hashable {
    case ink
    case brand
}

/// A value's artwork at both rungs. Either half may be absent.
public struct Marks: Hashable, Sendable {
    public let symbol: Mark?
    public let lockup: Mark?

    public init(symbol: Mark? = nil, lockup: Mark? = nil) {
        self.symbol = symbol
        self.lockup = lockup
    }

    public static let none = Marks()
}

extension DynamicRange {
    public var marks: Marks {
        switch self {
        case .dolbyVision: Marks(symbol: .dolby, lockup: .dolbyvision)
        case .hdr10: Marks(symbol: .hdr10, lockup: .hdr10)
        case .hdr10Plus: Marks(symbol: .hdr10plus, lockup: .hdr10plus)
        case .sdr, .hlg: .none
        }
    }
}

extension Resolution {
    /// Only 4K has a mark, and only at the rail: the poster rung keeps the
    /// text "4K", which reads where a 23:4 wordmark would be a hairline.
    public var marks: Marks {
        switch self {
        case .p2160: Marks(lockup: .ultrahd)
        default: .none
        }
    }
}

extension ObjectAudio {
    public var marks: Marks {
        switch self {
        case .atmos: Marks(symbol: .dolby, lockup: .dolbyatmos)
        case .dtsX: Marks(symbol: .dts, lockup: .dtswordmark)
        }
    }
}

extension AudioCodec {
    public var marks: Marks {
        switch self {
        case .trueHD: Marks(symbol: .dolby, lockup: .dolbytruehd)
        case .eac3: Marks(symbol: .dolby, lockup: .dolbydigitalplus)
        case .ac3: Marks(symbol: .dolby, lockup: .dolbydigital)
        case .dts: Marks(symbol: .dts, lockup: .dtswordmark)
        case .dtsHDMA: Marks(symbol: .dts, lockup: .dtshdma)
        case .dtsHDHRA: Marks(symbol: .dts)
        case .flac: Marks(lockup: .flac)
        case .opus: Marks(lockup: .opus)
        case .aac, .pcm, .alac, .mp3, .mp2, .vorbis: .none
        }
    }

    /// The word left over once the brand's symbol has said its part:
    /// "TrueHD" beside the double-D, "HD MA" beside dts, nothing beside dts
    /// for plain DTS. Codecs without a symbol keep their whole label.
    var wordBesideSymbol: String {
        switch self {
        case .dts: ""
        case .dtsHDMA: "HD MA"
        case .dtsHDHRA: "HD HRA"
        default: label
        }
    }
}

extension Tier {
    /// The disc marks. A 4K-sourced disc wears the Ultra HD Blu-ray mark,
    /// which is why the strip hands the tier chip its resolution.
    public func marks(at resolution: Resolution?) -> Marks {
        switch self {
        case .bluray, .remux:
            resolution == .p2160
                ? Marks(symbol: .blurayglyph, lockup: .ultrahdbluray)
                : Marks(symbol: .blurayglyph, lockup: .bluray)
        case .dvd: Marks(symbol: .dvd, lockup: .dvd)
        case .webdl, .webrip, .hdtv, .cam: .none
        }
    }
}

extension Lang {
    /// The two Spanishes the house tells apart: Spain wears its flag; Latin
    /// America has no single flag and stays a word.
    public var marks: Marks {
        rawValue == "es-ES" ? Marks(symbol: .flages, lockup: .flages) : .none
    }
}

extension Cut {
    public var marks: Marks {
        self == .imax ? Marks(symbol: .imax, lockup: .imax) : .none
    }
}
