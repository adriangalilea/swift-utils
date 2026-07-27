import AppKit
import SwiftUI

/// The interactive keymap surface behind `CheatSheetPanel`. Keyboard-first
/// by construction: the filter field GRABS focus on open (type immediately),
/// ↑/↓ move a selection through the filtered rows, ⏎ fires the selection.
/// While typing, bare keys belong to the field; chorded combos (⌘/⌃/⌥)
/// still press-to-flash and fire. Every combo chip removes on hover-x,
/// every row records a new combo in place, conflicts are reported inline
/// with the owner's name.
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
    let sections: [ActionSection<A>]
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
    @FocusState private var filterFocused: Bool
    /// Index into `visible` - the cursor ↑/↓ drive and ⏎ fires.
    @State private var selection: Int?

    /// The filtered actions in display order - the one list the cursor
    /// walks, the sections merely render it in groups.
    private var visible: [A] {
        sections.flatMap { $0.actions.filter(matchesQuery) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Filter actions", bundle: .module), text: $query)
                    .textFieldStyle(.plain)
                    .focused($filterFocused)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.return) { fireSelection() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(filterFocused ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
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
        .onAppear {
            installPressMonitor()
            // Keyboard-first: the panel opens ready to filter.
            filterFocused = true
        }
        .onDisappear(perform: removePressMonitor)
        .onChange(of: query) { _, newQuery in
            // Typing re-anchors the cursor: first match while filtering,
            // no selection on an empty query (the full reference state).
            selection = newQuery.isEmpty || visible.isEmpty ? nil : 0
        }
    }

    private func matchesQuery(_ action: A) -> Bool {
        query.isEmpty || action.spec.title.localizedCaseInsensitiveContains(query)
    }

    private func move(_ delta: Int) {
        let rows = visible
        guard !rows.isEmpty else { return }
        selection = ((selection ?? -1) + delta + rows.count) % rows.count
    }

    private func fireSelection() -> KeyPress.Result {
        let rows = visible
        guard let selection, rows.indices.contains(selection) else { return .ignored }
        let action = rows[selection]
        flash(action)
        perform?(action)
        return .handled
    }

    private func isSelected(_ action: A) -> Bool {
        guard let selection, visible.indices.contains(selection) else { return false }
        return visible[selection] == action
    }

    private func staticSection(_ name: String, _ rows: [StaticShortcut]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.caption.smallCaps().weight(.semibold))
                .foregroundStyle(.secondary)
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
                .font(.caption.smallCaps().weight(.semibold))
                .foregroundStyle(.secondary)
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
            flashed == action || isSelected(action) ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
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
                AddSlot {
                    conflict = nil
                    recording = (action, plane)
                }
            }
        }
    }

    // MARK: - Press-to-flash

    private func installPressMonitor() {
        guard flashOnPress, pressMonitor == nil else { return }
        pressMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard recording == nil, let pressed = KeyCombo(event: event) else { return false }
                // The focused filter field owns bare keys and shift-combos -
                // typing must type. Chorded combos can't be typed, so they
                // still teach by doing.
                if filterFocused, pressed.eventModifiers.isDisjoint(with: [.command, .control, .option]) {
                    return false
                }
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

/// The ＋ that records a new combo - a visible slot, not a ghost: a filled
/// circle that brightens and sharpens on hover so it reads as pressable.
private struct AddSlot: View {
    let arm: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: arm) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 18, height: 18)
                .background(.white.opacity(hovering ? 0.22 : 0.09), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
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
    let sections: [ActionSection<A>]
    let perform: ((A) -> Void)?
    let extras: [(name: String, rows: [StaticShortcut])]

    /// `perform` non-nil makes a pressed combo FIRE while the panel is up
    /// (teach by doing); nil just flashes the row. `sections` defaults to
    /// the registry's grouping - pass more when some actions live outside
    /// `A.sections`. `extras` documents the structural keys that aren't
    /// registry actions.
    public init(
        store: KeymapStore<A>,
        sections: [ActionSection<A>] = A.sections,
        perform: ((A) -> Void)? = nil,
        extras: [(name: String, rows: [StaticShortcut])] = []
    ) {
        self.store = store
        self.sections = sections
        self.perform = perform
        self.extras = extras
    }

    public var body: some View {
        KeymapEditor(store: store, sections: sections, flashOnPress: true, perform: perform, extras: extras)
            .padding()
            .frame(minWidth: 440, minHeight: 320)
    }
}
