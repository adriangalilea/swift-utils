import AppKit
import SwiftUI

/// The one keymap surface, hosted twice: `CheatSheetPanel` (floating
/// reference, press-to-flash) and `KeymapSettingsPane` (Settings, plus
/// family prefixes and Reset All). Reference and editor are the same rows:
/// every combo chip removes on hover-x, every row records a new combo in
/// place, conflicts are reported inline with the owner's name.
/// A literal reference row for keys that aren't registry actions - the
/// structural layer (Tab, arrows, Esc ladders) an app documents verbatim.
public struct StaticShortcut: Sendable {
    public let keys: String
    public let what: String
    public init(_ keys: String, _ what: String) {
        self.keys = keys
        self.what = what
    }
}

struct KeymapEditor<A: ActionSet>: View {
    let store: KeymapStore<A>
    /// Highlight (and optionally fire) the row whose combo is pressed while
    /// the surface is visible - the panel teaches by doing.
    let flashOnPress: Bool
    let perform: ((A) -> Void)?
    /// Structural rows appended after the registry sections, read-only.
    let extras: [(name: String, rows: [StaticShortcut])]

    @State private var query = ""
    @State private var recording: (action: A, plane: ComboPlane)?
    @State private var conflict: (action: A, message: String)?
    @State private var flashed: A?
    @State private var pressMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(String(localized: "Filter actions", bundle: .module), text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(A.sections.enumerated()), id: \.offset) { _, section in
                        let actions = section.actions.filter(matchesQuery)
                        if !actions.isEmpty {
                            sectionView(section.name, actions)
                        }
                    }
                    ForEach(Array(extras.enumerated()), id: \.offset) { _, extra in
                        let rows = extra.rows.filter { query.isEmpty || $0.what.localizedCaseInsensitiveContains(query) }
                        if !rows.isEmpty {
                            staticSection(extra.name, rows)
                        }
                    }
                }
            }
        }
        .onAppear(perform: installPressMonitor)
        .onDisappear(perform: removePressMonitor)
    }

    private func matchesQuery(_ action: A) -> Bool {
        query.isEmpty || action.spec.title.localizedCaseInsensitiveContains(query)
    }

    private func staticSection(_ name: String, _ rows: [StaticShortcut]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.caption.smallCaps())
                .foregroundStyle(.tertiary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Text(row.what)
                    Spacer()
                    ShortcutBadge(row.keys)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
            }
        }
    }

    private func sectionView(_ name: String, _ actions: [A]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.caption.smallCaps())
                .foregroundStyle(.tertiary)
            ForEach(actions, id: \.self, content: row)
        }
    }

    private func row(_ action: A) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: action.spec.symbol)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(action.spec.title)
                Spacer()
                planeChips(action, .local)
                Divider().frame(height: 12)
                planeChips(action, .global)
                if store.isCustomized(action) {
                    Button {
                        store.reset(action)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Reset to defaults", bundle: .module))
                }
            }
            if let conflict, conflict.action == action {
                Text(conflict.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 26)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            flashed == action ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    /// One plane's chips + its add slot. Global chips carry the globe.
    @ViewBuilder
    private func planeChips(_ action: A, _ plane: ComboPlane) -> some View {
        HStack(spacing: 4) {
            if plane == .global {
                Image(systemName: "globe")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help(String(localized: "System-wide", bundle: .module))
            }
            ForEach(store.combos(for: action, plane), id: \.self) { combo in
                ComboChip(combo) {
                    store.remove(combo, plane: plane, from: action)
                }
            }
            if recording?.action == action, recording?.plane == plane {
                RecordingChip { combo in
                    recording = nil
                    if let combo, let owner = store.add(combo, plane: plane, to: action) {
                        conflict = (action, String(localized: "\(combo.display) is already \(owner)", bundle: .module))
                    }
                }
            } else {
                Button {
                    conflict = nil
                    recording = (action, plane)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Press-to-flash

    private func installPressMonitor() {
        guard flashOnPress, pressMonitor == nil else { return }
        pressMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard recording == nil, let pressed = KeyCombo(event: event) else { return false }
                guard let action = A.allCases.first(where: { candidate in
                    store.combos(for: candidate, .local).contains(pressed)
                        || store.combos(for: candidate, .global).contains(pressed)
                }) else { return false }
                flash(action)
                perform?(action)
                return true
            }
            return handled ? nil : event
        }
    }

    private func removePressMonitor() {
        if let pressMonitor { NSEvent.removeMonitor(pressMonitor) }
        pressMonitor = nil
    }

    private func flash(_ action: A) {
        flashed = action
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            if flashed == action { flashed = nil }
        }
    }
}

/// The add slot while armed: captures the next keyDown as the new combo.
/// Esc cancels. Bare modifiers don't resolve (KeyCombo(event:) is nil) so
/// holding ⌘ while choosing the key works naturally.
private struct RecordingChip: View {
    let finish: (KeyCombo?) -> Void
    @State private var monitor: Any?

    var body: some View {
        Text(String(localized: "press keys…", bundle: .module))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.selection, in: RoundedRectangle(cornerRadius: 4))
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    MainActor.assumeIsolated {
                        if event.keyCode == 53 { // esc
                            finish(nil)
                        } else if let combo = KeyCombo(event: event) {
                            finish(combo)
                        } else {
                            return
                        }
                    }
                    return nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

// MARK: - The two hosts

/// The floating reference: every binding, filterable, press-to-flash.
/// Generated from the registry + the live store, so it can never drift.
public struct CheatSheetPanel<A: ActionSet>: View {
    let store: KeymapStore<A>
    let perform: ((A) -> Void)?
    let extras: [(name: String, rows: [StaticShortcut])]

    /// `perform` non-nil makes a pressed combo FIRE while the panel is up
    /// (teach by doing); nil just flashes the row. `extras` documents the
    /// structural keys that aren't registry actions.
    public init(
        store: KeymapStore<A>,
        perform: ((A) -> Void)? = nil,
        extras: [(name: String, rows: [StaticShortcut])] = []
    ) {
        self.store = store
        self.perform = perform
        self.extras = extras
    }

    public var body: some View {
        KeymapEditor(store: store, flashOnPress: true, perform: perform, extras: extras)
            .padding()
            .frame(minWidth: 440, minHeight: 320)
    }
}
