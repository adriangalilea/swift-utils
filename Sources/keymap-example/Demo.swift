import AppKit
import Ink
import Keymap
import SwiftUI

// The window: a toolbar hugging the top edge (its tips ask for .top and have no
// room, so they flip below), a transport bar hugging the bottom (.bottom, flips
// above), a sidebar toggle against the leading edge (.leading, flips after), an
// inspector toggle against the trailing edge (.trailing, flips before), the
// reveal button in the middle (.top, with room), and a list whose selected row
// floats its labeled actions to the trailing side.

@MainActor @Observable
final class Model {
    let store = KeymapStore<Command>()
    let monitor = RevealMonitor()
    var fired: Command?
    var selected = 0
    @ObservationIgnored private var routing: (LocalKeyRouter<Command>, GlobalHotkeys<Command>)?

    init() {
        routing = (
            LocalKeyRouter(store: store, perform: { [weak self] in self?.perform($0) }),
            GlobalHotkeys(store: store, perform: { [weak self] in self?.perform($0) })
        )
    }

    func perform(_ action: Command) {
        switch action {
        case .reveal: monitor.bareReveal.toggle()
        case .revealGlobals: monitor.globalReveal.toggle()
        case .play, .previous, .next, .search, .favorite, .share, .inspector, .sidebar:
            fired = action
        }
    }
}

struct Tool: View {
    let action: Command
    let edge: Edge
    let model: Model

    var body: some View {
        Button {
            model.perform(action)
        } label: {
            Image(systemName: action.spec.symbol)
        }
        .buttonStyle(.inkTool)
        .shortcutTip(action, model.store, extra: action == .play ? [playMediaKey] : [], edge: edge)
    }
}

struct DemoView: View {
    let model: Model
    private let rows = ["First track", "Second track", "Third track"]

    private var rowActions: [ShortcutTip.Item] {
        [
            ShortcutTip.Item(
                chords: model.store.chords(for: .play) + [playMediaKey], label: "Play"),
            ShortcutTip.Item(chords: model.store.chords(for: .favorite), label: "Favorite"),
            ShortcutTip.Item(chords: model.store.chords(for: .share), label: "Share"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: .inkGap) {
                ForEach([Command.search, .favorite, .share], id: \.self) {
                    Tool(action: $0, edge: .top, model: model)
                }
                Spacer()
            }
            .padding(.inkTight)
            HStack(spacing: 0) {
                Tool(action: .sidebar, edge: .leading, model: model).padding(.inkTight)
                Spacer()
                VStack(spacing: .inkBlock) {
                    Button("Reveal Shortcuts") { model.perform(.reveal) }
                        .buttonStyle(.ink)
                        .shortcutTip(Command.reveal, model.store, edge: .top)
                    VStack(spacing: .inkTight) {
                        ForEach(rows.indices, id: \.self) { i in
                            Text(rows[i])
                                .frame(width: 220, alignment: .leading)
                                .padding(.inkTight)
                                .background(
                                    i == model.selected ? Color.inkSelection : .clear,
                                    in: .rect(cornerRadius: .inkRow)
                                )
                                .contentShape(.rect)
                                .onTapGesture { model.selected = i }
                                .shortcutActions(
                                    "row", rowActions, present: i == model.selected,
                                    edge: .trailing)
                        }
                    }
                    Text(model.fired.map { "fired: \($0.spec.title)" } ?? "nothing fired yet")
                        .foregroundStyle(.secondary)
                    Text(
                        "? toggles the bare reveal · hold ⌘ ⇧ ⌥ ⌃ for their layers · ⌃⌥⌘/ the global forms, from any app"
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                Spacer()
                Tool(action: .inspector, edge: .trailing, model: model).padding(.inkTight)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: .inkGap) {
                Spacer()
                ForEach([Command.previous, .play, .next], id: \.self) {
                    Tool(action: $0, edge: .bottom, model: model)
                }
                Spacer()
            }
            .padding(.inkTight)
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

struct DemoApp: App {
    @State private var model = Model()

    var body: some Scene {
        WindowGroup("keymap demo") {
            DemoView(model: model)
                .shortcutTipLayer()
                .onModifierKeysChanged(mask: [.command, .shift, .option, .control]) { _, held in
                    model.monitor.flags = held
                }
                .environment(model.monitor)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}
