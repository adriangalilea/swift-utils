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
    /// The two plane columns are FIXED so every row aligns and nothing
    /// shifts as chips come and go; the reset slot is always reserved.
    private static var localColumn: CGFloat { 168 }
    private static var globalColumn: CGFloat { 148 }
    private static var resetColumn: CGFloat { 18 }

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
    /// Index into `visible` - the cursor ↑/↓ drive and ⏎ fires.
    @State private var selection: Int?

    /// The filtered actions in display order - the one list the cursor
    /// walks, the sections merely render it in groups.
    private var visible: [A] {
        sections.flatMap { $0.actions.filter(matchesQuery) }
    }

    /// The cursor is home (no row selected) - the input carries the visible
    /// focus. The FIELD keeps keyboard focus the whole time either way; the
    /// row cursor is virtual.
    private var cursorAtField: Bool { selection == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The "field" is RENDERED state, not a TextField: the panel is
            // the one keyboard owner (its monitor), so there is no focus
            // system in play - no first-responder races, no select-all on
            // focus, no gap a keystroke can fall into. From the first key.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                if query.isEmpty {
                    Text(String(localized: "Filter actions", bundle: .module))
                        .foregroundStyle(.secondary)
                } else {
                    Text(query)
                }
                // The caret: a quiet bar, present while the cursor is home.
                if cursorAtField {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.inkEdge)
                        .frame(width: 2, height: 14)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(cursorAtField ? Color.inkRaised : Color.inkRest, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if cursorAtField {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.inkEdge, lineWidth: 1)
                }
            }
            columnHeaders
            scrollBody
        }
        .onAppear(perform: installPressMonitor)
        .onDisappear(perform: removePressMonitor)
        .onChange(of: query) { _, newQuery in
            // Typing re-anchors the cursor: first match while filtering,
            // no selection on an empty query (the full reference state).
            selection = newQuery.isEmpty || visible.isEmpty ? nil : 0
        }
    }

    /// Which viewport edges have content hidden beyond them - the fade
    /// exists ONLY there. At rest at the top there is nothing above, so the
    /// first rows render whole; scroll a pixel and the fade eases in.
    private struct ScrollEdges: Equatable {
        var top = false
        var bottom = false
    }
    @State private var hiddenBeyond = ScrollEdges()

    private var scrollBody: some View {
        scrollContent
            .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                ScrollEdges(
                    top: geometry.contentOffset.y + geometry.contentInsets.top > 4,
                    bottom: geometry.contentOffset.y + geometry.containerSize.height
                        < geometry.contentSize.height - 4
                )
            } action: { _, edges in
                hiddenBeyond = edges
            }
            // Content never hard-crops mid-scroll: a fade mask melts it into
            // the glass, but only at edges that actually hide content.
            // (scrollEdgeEffectStyle only renders under real edge bars - a
            // padded panel has none.)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: hiddenBeyond.top ? 16 : 0)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: hiddenBeyond.bottom ? 16 : 0)
                }
                .animation(.easeOut(duration: 0.15), value: hiddenBeyond)
            }
    }

    private var scrollContent: some View {
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

    private func matchesQuery(_ action: A) -> Bool {
        query.isEmpty || action.spec.title.localizedCaseInsensitiveContains(query)
    }

    private func move(_ delta: Int) {
        let rows = visible
        guard !rows.isEmpty else { return }
        if delta > 0 {
            selection = min((selection ?? -1) + delta, rows.count - 1)
        } else {
            // ↑ past the first row hands the cursor back to the input -
            // no wrapping teleports.
            let next = (selection ?? 0) + delta
            selection = next < 0 ? nil : next
        }
    }

    private func fireSelection() -> Bool {
        let rows = visible
        guard let selection, rows.indices.contains(selection) else { return false }
        let action = rows[selection]
        flash(action)
        perform?(action)
        return true
    }

    private func isSelected(_ action: A) -> Bool {
        guard let selection, visible.indices.contains(selection) else { return false }
        return visible[selection] == action
    }

    /// The one explanation of the two planes - a header instead of a
    /// per-row glyph: labeled columns, tooltips carrying the long form.
    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Spacer()
            Text(String(localized: "In-app", bundle: .module))
                .frame(width: Self.localColumn, alignment: .leading)
                .help(String(localized: "Works while this app is frontmost", bundle: .module))
            Label(String(localized: "From any app", bundle: .module), systemImage: "globe")
                .frame(width: Self.globalColumn, alignment: .leading)
                .help(String(localized: "System-wide - works even when this app is in the background", bundle: .module))
            Color.clear.frame(width: Self.resetColumn, height: 1)
        }
        .planeHeaderStyle()
        .padding(.horizontal, 6)
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
                    .frame(width: Self.localColumn, alignment: .leading)
                planeChips(action, .global)
                    .frame(width: Self.globalColumn, alignment: .leading)
                Button {
                    store.reset(action)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .frame(width: Self.resetColumn)
                .opacity(store.isCustomized(action) ? 1 : 0)
                .disabled(!store.isCustomized(action))
                .help(String(localized: "Reset to defaults", bundle: .module))
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
        .background {
            if flashed == action || isSelected(action) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.inkSelection)
                    .strokeBorder(.inkEdge, lineWidth: 1)
            }
        }
    }

    /// One plane's chips + its add slot. ＋ leads so it stays put as chips
    /// come and go (the settings grid's rule); the column header carries
    /// the plane's meaning.
    @ViewBuilder
    private func planeChips(_ action: A, _ plane: ComboPlane) -> some View {
        HStack(spacing: 4) {
            AddSlot {
                conflict = nil
                recording = (action, plane)
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
            }
        }
    }

    // MARK: - Press-to-flash

    private func installPressMonitor() {
        guard flashOnPress, pressMonitor == nil else { return }
        pressMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard recording == nil else { return false }
                // Esc is the HOST's key - dismissal - and local monitors run
                // newest-first, so the panel must explicitly disown it or
                // the typing catch-all below would swallow it.
                if event.keyCode == 53 { return false }
                // Panel navigation first - claimed HERE because menu key
                // equivalents dispatch before any focused-view handler, and
                // bare arrows are often an app action's menu representative.
                switch event.keyCode {
                case 125: move(1); return true // ↓
                case 126: move(-1); return true // ↑
                case 36: return fireSelection() // ⏎
                default: break
                }
                guard let pressed = KeyCombo(event: event) else { return false }
                // Editing verbs on the query - the panel IS the field.
                if event.keyCode == 51 { // ⌫; ⌘⌫ clears
                    if event.modifierFlags.contains(.command) { query = "" }
                    else if !query.isEmpty { query.removeLast() }
                    return true
                }
                if event.modifierFlags.contains(.command),
                   event.charactersIgnoringModifiers == "v" {
                    query += NSPasteboard.general.string(forType: .string) ?? ""
                    return true
                }
                // Bare keys are TYPING, unconditionally - appended straight
                // to the query, never fired as actions, never lost.
                if pressed.eventModifiers.isDisjoint(with: [.command, .control, .option]) {
                    if let typed = event.characters {
                        query += String(typed.unicodeScalars.filter { scalar in
                            !scalar.properties.isDefaultIgnorableCodePoint
                                && scalar.value >= 0x20 && scalar.value < 0xF700
                        }.map(Character.init))
                    }
                    return true
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
                .background(hovering ? Color.inkHover : Color.inkRest, in: Circle())
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
            .background(Color.inkRaised, in: RoundedRectangle(cornerRadius: 4))
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
