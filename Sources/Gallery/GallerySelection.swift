// ============================================================ the selection kernel
//
// Framework-free (the "extract the kernel, not the component" doctrine):
// pure state over (orderedItems, Set), zero UI, zero Keymap. The host
// binds inputs - a macOS host binds onKeyPress and clicks; a tvOS host
// doesn't use `move` at all (the focus engine drives) but keeps the same
// selection grammar.
//
// The invariants that cost real field bugs, kept as law:
// - selection reads back in BROWSE ORDER, never Set order.
// - selectAll lands anchor + cursor on the browse HEAD, so the next
//   enter/space/shift-click is deterministic (Set.first is not an order).
// - open honors the cursor only while it points INSIDE the selection -
//   a deselected grid must never open a ghost.

public struct GallerySelection<ID: Hashable & Sendable>: Equatable, Sendable {
    public var selected: Set<ID> = []
    /// The shift-range anchor (last plain click / replace).
    public var anchor: ID?
    /// The keyboard cursor (last touched item).
    public var cursor: ID?

    public init() {}

    public enum Mode: Sendable { case replace, toggle, range }

    /// THE selection verb - every click and key lands here. `range` spans
    /// from the anchor through the browse order, Finder/Photos grammar.
    public mutating func select(_ id: ID, _ mode: Mode, order: [ID]) {
        switch mode {
        case .replace:
            selected = [id]
            anchor = id
        case .toggle:
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            anchor = id
        case .range:
            guard let ai = order.firstIndex(of: anchor ?? id),
                  let bi = order.firstIndex(of: id) else {
                selected = [id]
                anchor = id
                break
            }
            selected = Set(order[min(ai, bi)...max(ai, bi)])
        }
        cursor = id
    }

    public mutating func selectAll(order: [ID]) {
        selected = Set(order)
        anchor = order.first
        cursor = order.first
    }

    public mutating func clear() {
        selected = []
        anchor = nil
        cursor = nil
    }

    /// The selected ids IN BROWSE ORDER (stale ids drop out on their own).
    public func selectedInOrder(_ order: [ID]) -> [ID] {
        order.filter(selected.contains)
    }

    /// 2D cursor walk: dx steps the flat browse order (clamped at the
    /// ends), dy steps rows keeping the column (clamped to the shorter
    /// row). Nothing under the cursor → land on an end of the list.
    /// Returns the id to scroll into view (nil = no move happened).
    @discardableResult
    public mutating func move(dx: Int, dy: Int, extend: Bool, order: [ID], rows: [[ID]]) -> ID? {
        guard !order.isEmpty else { return nil }
        guard let cur = cursor, order.contains(cur) else {
            let id = (dx + dy) < 0 ? order.last! : order.first!
            select(id, .replace, order: order)
            return id
        }
        var target: ID?
        if dx != 0, let i = order.firstIndex(of: cur) {
            target = order[max(0, min(order.count - 1, i + dx))]
        } else if dy != 0 {
            for (r, row) in rows.enumerated() {
                guard let col = row.firstIndex(of: cur) else { continue }
                let nr = max(0, min(rows.count - 1, r + dy))
                if nr != r, !rows[nr].isEmpty {
                    target = rows[nr][min(col, rows[nr].count - 1)]
                }
                break
            }
        }
        guard let target else { return nil }
        select(target, extend ? .range : .replace, order: order)
        return target
    }

    /// What ↵/space should open: the cursor while it is inside the
    /// selection, else the selection's browse-order head, else nil (let
    /// the key fall through).
    public func openTarget(order: [ID]) -> ID? {
        if let cur = cursor, selected.contains(cur) { return cur }
        return selectedInOrder(order).first
    }
}
