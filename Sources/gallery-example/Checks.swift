import CoreGraphics
import Foundation
import Gallery

// The kernel invariants, asserted over deterministic synthetic data. Every
// law here was paid for in a consumer app; a violation is a regression in
// extracted behavior, never a flake.

/// Deterministic aspects (seeded splitmix64) - the gate must fail the same
/// way twice.
func syntheticAspects(_ n: Int, seed: UInt64 = 9) -> [CGFloat] {
    var state = seed
    func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    // The shapes a real library holds: posters, stills, squares, the odd
    // panorama/sliver that the clamp must tame.
    let pool: [CGFloat] = [2.0 / 3.0, 16.0 / 9.0, 1.0, 4.0 / 3.0, 3.0 / 4.0, 2.39, 9.0 / 16.0, 3.4, 0.2]
    return (0..<n).map { _ in pool[Int(next() % UInt64(pool.count))] }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("gallery-example check FAILED: " + message + "\n").utf8))
    exit(1)
}

func runChecks() -> Never {
    let W: CGFloat = 1800
    let target: CGFloat = 320
    let spacing: CGFloat = 24
    let aspects = syntheticAspects(200).map { GalleryPack.clamped($0) }

    // ---- clamp: the two extremes in the pool must have been tamed ----
    for a in aspects where !(0.45...2.6).contains(a) { fail("clamp leaked aspect \(a)") }

    // ---- justified rows: every row fills the width, no row over target ----
    let rows = GalleryPack.justifiedRows(aspects: aspects, width: W, targetHeight: target, spacing: spacing)
    if rows.isEmpty { fail("no rows for 200 items") }
    var covered = 0
    for (i, row) in rows.enumerated() {
        let filled = row.widths.reduce(0, +) + spacing * CGFloat(row.widths.count - 1)
        let last = i == rows.count - 1
        if !last, abs(filled - W) > 0.5 { fail("row \(i) fills \(filled), want \(W) ±0.5") }
        if last, filled > W + 0.5 { fail("last row overfills: \(filled) > \(W)") }
        if row.height > target + 0.001 { fail("row \(i) height \(row.height) exceeds target \(target)") }
        if row.range.lowerBound != covered { fail("row \(i) starts at \(row.range.lowerBound), want \(covered) (gap/overlap)") }
        if row.widths.count != row.range.count { fail("row \(i) widths/range mismatch") }
        covered = row.range.upperBound
    }
    if covered != aspects.count { fail("rows cover \(covered) of \(aspects.count) items") }

    // ---- prefix stability: appending items only re-packs the old LAST row.
    // This is the law tvOS paging stands on (no reflow under the focus
    // engine), so it is checked at several split points, not one.
    for n in [30, 77, 120, 199] {
        let head = GalleryPack.justifiedRows(aspects: Array(aspects[..<n]), width: W, targetHeight: target, spacing: spacing)
        for (i, row) in head.dropLast().enumerated() where row != rows[i] {
            fail("append instability: row \(i) of prefix \(n) changed after append")
        }
    }

    // ---- selection: the Finder/Photos grammar ----
    let order = Array(0..<20)
    var sel = GallerySelection<Int>()

    sel.select(5, .replace, order: order)
    sel.select(9, .range, order: order)
    if sel.selected != Set(5...9) { fail("range must span anchor...target: \(sel.selected)") }
    sel.select(2, .range, order: order)
    if sel.selected != Set(2...5) { fail("range re-extends from the SAME anchor: \(sel.selected)") }

    sel.selectAll(order: order)
    if sel.anchor != 0 || sel.cursor != 0 { fail("selectAll must land anchor+cursor on the browse HEAD") }
    if sel.selectedInOrder(order) != order { fail("selectedInOrder must read back in browse order") }

    sel.select(7, .toggle, order: order)   // 7 leaves the selection
    if sel.selected.contains(7) { fail("toggle failed to remove") }
    if sel.openTarget(order: order) != 0 { fail("cursor outside selection: open must fall to the browse-order head") }
    sel.clear()
    if sel.openTarget(order: order) != nil { fail("empty selection must open nothing (never a ghost)") }

    // ---- 2D walk: dy keeps the column, clamped to the shorter row ----
    let walkRows = [[0, 1, 2, 3], [4, 5], [6, 7, 8]]
    sel.select(3, .replace, order: order)
    if sel.move(dx: 0, dy: 1, extend: false, order: order, rows: walkRows) != 5 {
        fail("dy from col 3 into a 2-wide row must clamp to its last column")
    }
    if sel.move(dx: 0, dy: 1, extend: false, order: order, rows: walkRows) != 7 {
        fail("dy keeps the column (col 1 → 7)")
    }
    if sel.move(dx: 0, dy: 1, extend: false, order: order, rows: walkRows) != nil {
        fail("dy past the last row must not move")
    }
    if sel.move(dx: 1, dy: 0, extend: false, order: order, rows: walkRows) != 8 {
        fail("dx steps the flat order")
    }
    sel.clear()
    if sel.move(dx: -1, dy: 0, extend: false, order: order, rows: walkRows) != 19 {
        fail("no cursor + negative step must land on the list END")
    }
    sel.select(4, .replace, order: order)
    _ = sel.move(dx: 0, dy: -1, extend: true, order: order, rows: walkRows)
    if sel.selected != Set(0...4) { fail("shift-move must extend from the anchor: \(sel.selected)") }

    print("gallery-example: all checks passed (\(rows.count) rows over \(aspects.count) items)")
    exit(0)
}
