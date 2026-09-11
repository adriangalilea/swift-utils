import SwiftUI

// WHICH MARK A VALUE WEARS. `Mark` (generated) is the catalog of artworks;
// this file is the one place a vocabulary value is bound to a symbol (the
// poster rung: the brand's own glyph or a small badge) and a lockup (the
// rail rung: the full logotype or the same badge). ARTWORK FIRST: a value
// with an entry is drawn, never written; a value with no entry becomes a
// drawn word-badge, the one shape words take in this family (Chips.swift).

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
    /// The tabler badges (MIT) at both rungs; 720p has no artwork anywhere
    /// and is drawn. The ULTRA HD wordmark stays in the catalog unbound.
    public var marks: Marks {
        switch self {
        case .sd: Marks(symbol: .badgesd, lockup: .badgesd)
        case .p720: .none
        case .p1080: Marks(symbol: .badgehd, lockup: .badgehd)
        case .p2160: Marks(symbol: .badge4k, lockup: .badge4k)
        case .p4320: Marks(symbol: .badge8k, lockup: .badge8k)
        }
    }
}

extension ObjectAudio {
    /// DTS:X has no free vector anywhere (the only one is CC BY-NC-SA):
    /// it is drawn.
    public var marks: Marks {
        switch self {
        case .atmos: Marks(symbol: .dolby, lockup: .dolbyatmos)
        case .dtsX: .none
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
