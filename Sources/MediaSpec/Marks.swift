import SwiftUI

// WHICH MARK A VALUE WEARS. `Mark` (generated) is the catalog of artworks;
// this file is the one place a vocabulary value is bound to a symbol (the
// poster rung: the brand's own glyph or a small badge) and a lockup (the
// rail rung: the full logotype or the same badge). ARTWORK FIRST: a value
// with an entry is drawn, never written; a value with no entry becomes a
// drawn word-badge, the one shape words take in this family (Chips.swift).

/// How a mark is coloured. `ink` follows the chip's foreground (one ink,
/// the flare rule); `brand` uses the mark's official hex; `gold` is the
/// disc-case metallic sticker (`Gold`): a near-black box, stroke and
/// letters in the metallic gradient, marks filled with the same gradient
/// as disc cases print them, flat gold below the rail. A mark with
/// intrinsic colours (the flag) ignores tone by construction.
public enum Tone: String, Codable, CaseIterable, Sendable, Hashable {
    case ink
    case brand
    case gold
}

/// The metallic gold of a disc-case sticker, retunable by a consumer:
/// the gradient's stops (about 135°, light to dark with a thin highlight
/// near the bottom edge), the flat gold used below the rail, and the box
/// ground.
public enum Gold {
    nonisolated(unsafe) public static var stops: [Gradient.Stop] = [
        .init(color: Color(red: 1.000, green: 0.945, blue: 0.659), location: 0),  // #FFF1A8
        .init(color: Color(red: 0.902, green: 0.706, blue: 0.133), location: 0.45),  // #E6B422
        .init(color: Color(red: 0.612, green: 0.478, blue: 0.106), location: 0.86),  // #9C7A1B
        .init(color: Color(red: 1.000, green: 0.902, blue: 0.502), location: 0.96),  // #FFE680
        .init(color: Color(red: 0.612, green: 0.478, blue: 0.106), location: 1),  // #9C7A1B
    ]
    /// The one gold below the rail, where a gradient has no room to read
    /// (#E6B422).
    nonisolated(unsafe) public static var flat = Color(red: 0.902, green: 0.706, blue: 0.133)
    /// The sticker's ground.
    nonisolated(unsafe) public static var ground = Color(white: 0.07)
    /// Stroke, relative to the family's 0.08h hairline.
    public static let strokeScale: CGFloat = 1.5

    public static var gradient: LinearGradient {
        LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
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
    /// Resolutions are DRAWN as disc-case badges (`Resolution.glyph` in
    /// Chips.swift): no free vector of the "4K ULTRA HD" badge exists and
    /// it is typography below the originality threshold. The tabler badges
    /// and the ULTRA HD wordmark stay in the catalog unbound.
    public var marks: Marks { .none }
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
