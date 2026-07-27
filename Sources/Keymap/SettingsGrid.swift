import AppKit
import Ink
import SwiftUI

/// Restore Defaults for a whole store - place it wherever the settings
/// surface ends. Stateless on purpose: conflicts already report inline at
/// the recording pill, so no reserved message line is needed.
public struct KeymapRestoreDefaults<A: ActionSet>: View {
    let store: KeymapStore<A>
    public init(store: KeymapStore<A>) { self.store = store }
    public var body: some View {
        HStack {
            Spacer()
            Button(String(localized: "Restore Defaults", bundle: .module)) {
                store.resetAll()
            }
        }
    }
}

/// What's being recorded right now - an action on one plane. Esc cancels.
private struct RecordTarget<A: ActionSet>: Equatable {
    let action: A
    let plane: ComboPlane
}

/// The whole binding table: ONE row per command, two aligned columns -
/// in-app and from any app - so an action is never listed twice. Grid keeps
/// the columns aligned across every category and the family rows. Drop it
/// in a Form Section; the app owns the Form and any app-specific sections
/// around it.
public struct KeymapGrid<A: ActionSet>: View {
    let store: KeymapStore<A>
    let sections: [ActionSection<A>]

    @State private var recording: RecordTarget<A>?
    @State private var capture: KeyCapture?
    @State private var message = ""

    /// `sections` defaults to the registry's own grouping; pass more groups
    /// when some actions live outside `A.sections` (selection verbs, etc.).
    public init(store: KeymapStore<A>, sections: [ActionSection<A>] = A.sections) {
        self.store = store
        self.sections = sections
    }

    // The modifier choices a family prefix can take. Plain member keys stay
    // the app's (a bare digit means something else), so a real modifier is
    // required in-app; "Off" is allowed system-wide only.
    private static var familyChoices: [(name: String, mods: EventModifiers)] {
        [
            ("⌘", .command), ("⌃", .control), ("⌥", .option),
            ("⇧⌘", [.shift, .command]), ("⌃⌘", [.control, .command]), ("⌥⌘", [.option, .command]),
            ("⌃⌥", [.control, .option]),
        ]
    }

    public var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
            GridRow {
                Color.clear.frame(maxWidth: .infinity, minHeight: 1)
                columnHeader(String(localized: "In-app", bundle: .module))
                columnHeader(String(localized: "From any app", bundle: .module))
                Color.clear.frame(width: 16, height: 1)
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                categoryHeader(section.name)
                ForEach(section.actions, id: \.self) { action in
                    actionRow(action)
                }
            }
            ForEach(store.families, id: \.id) { family in
                categoryHeader(family.name)
                familyRow(family)
            }
        }
        .padding(.vertical, 2)
        .onDisappear { stopRecording() }
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title).planeHeaderStyle()
    }

    /// A category label spanning the full width - the grouping without
    /// breaking column alignment.
    private func categoryHeader(_ name: String) -> some View {
        GridRow {
            Text(name.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .gridCellColumns(4)
                .padding(.top, 8)
        }
    }

    private func actionRow(_ action: A) -> some View {
        GridRow(alignment: .center) {
            Label(action.spec.title, systemImage: action.spec.symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
            planeCell(action, .local)
            planeCell(action, .global)
            resetButton(action)
        }
    }

    /// One plane's chips for an action, plus the ＋ recorder. Every command
    /// is bindable on both planes (in-app and system-wide).
    private func planeCell(_ action: A, _ plane: ComboPlane) -> some View {
        let combos = store.combos(for: action, plane)
        // ＋ leads (stays put as chips change) and is prominently separated
        // from the bound chips, which pack tight as one group.
        return HStack(spacing: 0) {
            addButton(action, plane)
            if !combos.isEmpty {
                HStack(spacing: 4) {
                    ForEach(combos, id: \.self) { combo in
                        ComboChip(combo.display) { store.remove(combo, plane: plane, from: action) }
                            // A global another running app owns is INERT -
                            // say so where the binding lives.
                            .opacity(plane == .global && store.deadGlobals.contains(combo) ? 0.4 : 1)
                            .help(plane == .global && store.deadGlobals.contains(combo)
                                ? String(localized: "Another app owns this system-wide right now - it won't fire", bundle: .module)
                                : "")
                    }
                }
                .padding(.leading, 14)
            }
        }
    }

    private func resetButton(_ action: A) -> some View {
        Button { store.reset(action) } label: {
            Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
        }
        .buttonStyle(.borderless)
        .opacity(store.isCustomized(action) ? 1 : 0)
        .disabled(!store.isCustomized(action))
        .help(String(localized: "Reset to defaults", bundle: .module))
    }

    private func familyRow(_ family: ComboFamily) -> some View {
        GridRow(alignment: .center) {
            Label(family.name, systemImage: "number.square")
                .frame(maxWidth: .infinity, alignment: .leading)
            familyPicker(family, .local, allowOff: false)
            familyPicker(family, .global, allowOff: true)
            Color.clear.frame(width: 16, height: 1)
        }
    }

    /// The family modifier picker (one per column) - a curated menu, since
    /// only the modifier varies, never the member keys. "Off" disables the
    /// system-wide column.
    private func familyPicker(_ family: ComboFamily, _ plane: ComboPlane, allowOff: Bool) -> some View {
        let range = "\(family.keys.first ?? "")–\(family.keys.last ?? "")"
        let current = store.familyModifier(family.id, plane)
        return Menu {
            if allowOff {
                Button(String(localized: "Off", bundle: .module)) {
                    store.setFamilyModifier(family.id, plane, to: [])
                }
            }
            ForEach(Self.familyChoices, id: \.name) { choice in
                Button("\(choice.name)\(range)") {
                    store.setFamilyModifier(family.id, plane, to: choice.mods)
                }
            }
        } label: {
            Text(current.isEmpty ? String(localized: "Off", bundle: .module) : "\(current.glyphs)\(range)")
                .font(.callout.monospaced())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func addButton(_ action: A, _ plane: ComboPlane) -> some View {
        let isRecording = recording == RecordTarget(action: action, plane: plane)
        // A rejected key (taken, or a global with no modifier) turns the pill
        // red and names the reason RIGHT HERE - feedback lives at the action.
        let rejected = isRecording && !message.isEmpty
        // Same capsule + fill as a combo chip, so the row reads as one family.
        return Button { beginRecording(action, plane) } label: {
            Group {
                if isRecording {
                    Text(rejected ? message : String(localized: "type a key…", bundle: .module))
                        .font(.caption)
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(rejected ? AnyShapeStyle(.white)
                : isRecording ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            // Idle is a square → the Capsule renders as a circle; recording
            // grows to a pill to fit its text.
            .frame(width: isRecording ? nil : 24, height: 24)
            .padding(.horizontal, isRecording ? 10 : 0)
            .background(
                rejected ? AnyShapeStyle(.red.opacity(0.9))
                    : isRecording ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.85)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private func beginRecording(_ action: A, _ plane: ComboPlane) {
        let target = RecordTarget(action: action, plane: plane)
        if recording == target {
            stopRecording()
            return
        }
        recording = target
        message = ""
        // A refused key (the STORE owns every binding rule) reports its
        // verdict and keeps listening; an accepted one ends the session.
        capture = KeyCapture(onCombo: { pressed in
            if let rejection = store.add(pressed, plane: target.plane, to: target.action) {
                message = rejection.message(for: pressed)
                return false
            }
            message = ""
            stopRecording()
            return true
        }, onCancel: stopRecording)
    }

    private func stopRecording() {
        recording = nil
        capture = nil
    }
}
