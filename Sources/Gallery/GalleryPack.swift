import CoreGraphics

// ============================================================ the layout kernel
//
// Framework-free: aspects in, geometry out. Two packers by design - justified
// rows (Lightroom's grammar: every row exactly fills the width, each item at
// its TRUE aspect, strict reading order - the shape a keyboard cursor or a
// focus engine can walk deterministically) and, in a later sprint,
// shortest-column-first masonry (the Pinterest look). Views and apps never
// re-derive this math; a second copy of a layout rule is how two surfaces
// drift.

public enum GalleryPack {
    /// One justified row: which items (a range into the caller's order),
    /// the row's exact-fit height, and each item's width at that height.
    public struct Row: Equatable, Sendable {
        public var range: Range<Int>
        public var height: CGFloat
        public var widths: [CGFloat]
        public init(range: Range<Int>, height: CGFloat, widths: [CGFloat]) {
            self.range = range
            self.height = height
            self.widths = widths
        }
    }

    /// The one aspect clamp: one extreme panorama or sliver must never own
    /// a whole row. Callers clamp BEFORE packing so layout and cell render
    /// read the same number.
    public static func clamped(_ aspect: CGFloat, to range: ClosedRange<CGFloat> = 0.45...2.6)
        -> CGFloat
    {
        max(range.lowerBound, min(range.upperBound, aspect))
    }

    /// Greedy justified rows: fill a row
    /// until its exact-fit height drops to the target, emit, repeat. The
    /// last row never stretches past the target. Deterministic and
    /// PREFIX-STABLE: a row is emitted the moment it fills, on its own
    /// items alone, so appending items can only extend or re-pack the old
    /// LAST row - everything above it is untouched. That property is what
    /// lets a paging consumer (tvOS) append without reflowing rows under
    /// the focus engine.
    public static func justifiedRows(
        aspects: [CGFloat], width W: CGFloat,
        targetHeight: CGFloat = 220, spacing: CGFloat = 8
    ) -> [Row] {
        guard W > 60, !aspects.isEmpty else { return [] }
        var rows: [Row] = []
        var start = 0
        var sumA: CGFloat = 0
        for (i, a) in aspects.enumerated() {
            sumA += a
            let count = i - start + 1
            let h = (W - spacing * CGFloat(count - 1)) / sumA
            if h <= targetHeight {
                rows.append(row(start..<(i + 1), height: h, aspects: aspects))
                start = i + 1
                sumA = 0
            }
        }
        if start < aspects.count {
            let count = aspects.count - start
            let h = min(targetHeight, (W - spacing * CGFloat(count - 1)) / sumA)
            rows.append(row(start..<aspects.count, height: h, aspects: aspects))
        }
        return rows
    }

    private static func row(_ r: Range<Int>, height: CGFloat, aspects: [CGFloat]) -> Row {
        Row(range: r, height: height, widths: aspects[r].map { height * $0 })
    }
}
