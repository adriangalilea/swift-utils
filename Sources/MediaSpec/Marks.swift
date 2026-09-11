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
    /// Only Dolby Vision is a brand mark. HDR10 and HDR10+ are boxed words
    /// drawn in the family's one badge geometry (their Commons artwork stays
    /// in the catalog as reference: a second stroke weight beside the drawn
    /// family reads as a second family).
    public var marks: Marks {
        switch self {
        case .dolbyVision: Marks(symbol: .dolby, lockup: .dolbyvision)
        case .sdr, .hlg, .hdr10, .hdr10Plus: .none
        }
    }
}

extension Resolution {
    /// The tabler badges at both rungs: 4K and 8K need real distinction and
    /// tabler's letterforms give it. Their stroke is 1.12 on the 24-grid,
    /// which over the badge's 14-unit box is the drawn family's 0.08h - one
    /// weight by construction. The chip scales the file so the BOX is h
    /// (see `Mark.boxScale`). 720p has no artwork and is drawn; the ULTRA
    /// HD wordmark stays in the catalog unbound.
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

extension Mark {
    /// How much taller than the chip a mark's FILE must render so its
    /// drawn box lands at the chip height. The tabler badges draw a 14-unit
    /// box inside a 24-unit grid (24/14); every other mark fills its
    /// viewBox and renders at the chip height as is.
    public var boxScale: CGFloat {
        switch self {
        case .badge4k, .badge8k, .badgehd, .badgesd: 24.0 / 14.0
        default: 1
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
    /// Flags are keyed by the REGION subtag, never the language: a language
    /// is not a country. Only Spain ships today.
    public var marks: Marks {
        region == "ES" ? Marks(symbol: .flages, lockup: .flages) : .none
    }
}

extension Cut {
    public var marks: Marks {
        self == .imax ? Marks(symbol: .imax, lockup: .imax) : .none
    }
}
