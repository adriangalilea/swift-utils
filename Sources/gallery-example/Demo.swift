import AppKit
import Gallery
import SwiftUI

// The windowed half: the real GalleryView over synthetic cells, wired the
// way a host app binds it - clicks through the 3-mode selection verb
// (⌘ toggles, ⇧ spans), arrows through the 2D walk (⇧ extends), ⌘A select
// all, esc clears. Selection IS the ring (one color, alpha only - the
// flare rule); there is no second focus treatment.

struct DemoItem: Identifiable {
    let id: Int
    let aspect: CGFloat
}

/// Row geometry the keyboard verbs read - plain vars on a plain class, the
/// non-observable home the GalleryView contract requires.
final class DemoGeometry {
    var rows: [[Int]] = []
}

struct DemoApp: App {
    var body: some Scene {
        WindowGroup("gallery-example") {
            DemoView()
                .frame(minWidth: 720, minHeight: 480)
        }
    }
}

struct DemoView: View {
    let items: [DemoItem] = syntheticAspects(200).enumerated().map { DemoItem(id: $0.offset, aspect: $0.element) }
    @State private var selection = GallerySelection<Int>()
    @State private var scrollTarget: Int?
    @State private var geometry = DemoGeometry()

    private var order: [Int] { items.map(\.id) }

    var body: some View {
        GalleryView(
            items: items,
            aspect: \.aspect,
            rowsChanged: { geometry.rows = $0 },
            scrollTarget: $scrollTarget
        ) { item, size in
            cell(item, size)
        }
        .padding(14)
        .background(Color.black)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { press in handle(press) }
    }

    private func cell(_ item: DemoItem, _ size: CGSize) -> some View {
        let selected = selection.selected.contains(item.id)
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hue: Double(item.id % 17) / 17, saturation: 0.35, brightness: 0.45))
            Text("\(item.id) · \(String(format: "%.2f", item.aspect))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .padding(6)
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(item.id == selection.cursor ? 0.9 : 0.6), lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            let mode: GallerySelection<Int>.Mode =
                flags.contains(.shift) ? .range : flags.contains(.command) ? .toggle : .replace
            selection.select(item.id, mode, order: order)
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let extend = press.modifiers.contains(.shift)
        func move(_ dx: Int, _ dy: Int) -> KeyPress.Result {
            scrollTarget = selection.move(dx: dx, dy: dy, extend: extend, order: order, rows: geometry.rows)
            return .handled
        }
        switch press.key {
        case .leftArrow: return move(-1, 0)
        case .rightArrow: return move(1, 0)
        case .upArrow: return move(0, -1)
        case .downArrow: return move(0, 1)
        case .escape:
            selection.clear()
            return .handled
        case "a" where press.modifiers.contains(.command):
            selection.selectAll(order: order)
            return .handled
        case .return:
            guard let id = selection.openTarget(order: order) else { return .ignored }
            print("open \(id)")
            return .handled
        default:
            return .ignored
        }
    }
}
