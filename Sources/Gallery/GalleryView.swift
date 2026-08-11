import Ink
import SwiftUI

// ============================================================ the gallery shell
//
// Observation-agnostic by contract: plain values in, closures out, no
// god-object, no Keymap. Works under @Observable and ObservableObject hosts
// alike, and on every platform - the structure is the cross-platform part
// (rows of true-aspect cells), the input grammar is the host's: macOS binds
// keys into GallerySelection, tvOS wraps cells in focusable buttons and
// lets the focus engine drive the same geometry.

public struct GalleryView<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let targetHeight: CGFloat
    let spacing: CGFloat
    let contentPadding: CGFloat
    let aspectClamp: ClosedRange<CGFloat>
    let rowFocusSections: Bool
    let aspect: (Item) -> CGFloat
    let rowsChanged: (([[Item.ID]]) -> Void)?
    let scrollTarget: Binding<Item.ID?>
    let cell: (Item, CGSize) -> Cell

    /// - Parameters:
    ///   - aspect: the item's width/height. Clamped through the ONE clamp
    ///     before packing, so layout and cell render the same number.
    ///   - rowsChanged: the row geometry, published every layout pass, for
    ///     a host binding a keyboard walk (GallerySelection.move takes it
    ///     as `rows`). Called during body evaluation - store it in
    ///     NON-observable state (an @ObservationIgnored var, a plain
    ///     class) or the assignment re-invalidates the very body that
    ///     made it.
    ///   - contentPadding: inset applied INSIDE the scroll content (the
    ///     rows scroll edge-to-edge under it), subtracted from the packing
    ///     width - padding the whole view instead would clip scrolling
    ///     rows at the inset box.
    ///   - rowFocusSections: tvOS focus fallback - each row becomes a
    ///     .focusSection(), so vertical moves always land in the ADJACENT
    ///     row (nearest cell within it) instead of jumping by raw
    ///     proximity across ragged edges. Off by default: trust the
    ///     engine first, flip this on field evidence.
    ///   - scrollTarget: a one-shot scroll-into-view request (the moved
    ///     cursor's id); the view scrolls its row and nils it. tvOS hosts
    ///     skip it - the focus engine scrolls for them.
    public init(
        items: [Item],
        targetHeight: CGFloat = 220,
        spacing: CGFloat = 8,
        contentPadding: CGFloat = 0,
        aspectClamp: ClosedRange<CGFloat> = 0.45...2.6,
        rowFocusSections: Bool = false,
        aspect: @escaping (Item) -> CGFloat,
        rowsChanged: (([[Item.ID]]) -> Void)? = nil,
        scrollTarget: Binding<Item.ID?> = .constant(nil),
        @ViewBuilder cell: @escaping (Item, CGSize) -> Cell
    ) {
        self.items = items
        self.targetHeight = targetHeight
        self.spacing = spacing
        self.contentPadding = contentPadding
        self.aspectClamp = aspectClamp
        self.rowFocusSections = rowFocusSections
        self.aspect = aspect
        self.rowsChanged = rowsChanged
        self.scrollTarget = scrollTarget
        self.cell = cell
    }

    public var body: some View {
        GeometryReader { geo in
            let aspects = items.map { GalleryPack.clamped(aspect($0), to: aspectClamp) }
            let rows = GalleryPack.justifiedRows(
                aspects: aspects, width: geo.size.width - contentPadding * 2,
                targetHeight: targetHeight, spacing: spacing
            )
            // Register the row geometry for the host's keyboard verbs -
            // plain bookkeeping during body evaluation, never observable
            // state (see the init doc).
            let _ = rowsChanged?(rows.map { row in row.range.map { items[$0].id } })
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: spacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { ri, row in
                            rowView(ri, row)
                        }
                    }
                    .padding(contentPadding)
                }
                .onChange(of: scrollTarget.wrappedValue) { _, target in
                    guard let target,
                          let ri = rows.firstIndex(where: { row in
                              row.range.contains { items[$0].id == target }
                          })
                    else { return }
                    withAnimation(.inkFlick) { proxy.scrollTo(ri) }
                    scrollTarget.wrappedValue = nil
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ ri: Int, _ row: GalleryPack.Row) -> some View {
        let content = HStack(spacing: spacing) {
            ForEach(rowSlice(row), id: \.item.id) { entry in
                cell(entry.item, CGSize(width: entry.width, height: row.height))
                    .frame(width: entry.width, height: row.height)
            }
        }
        .id(ri)
        if rowFocusSections {
            content.focusSection()
        } else {
            content
        }
    }

    private func rowSlice(_ row: GalleryPack.Row) -> [(item: Item, width: CGFloat)] {
        row.range.map { (items[$0], row.widths[$0 - row.range.lowerBound]) }
    }
}
