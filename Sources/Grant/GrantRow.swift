#if os(macOS)
    import SwiftUI

    /// The one row every grant surface wears: icon, title + why, a live
    /// checkmark or the standing's action. SELF-SUFFICIENT by design -
    /// it reads `grant.standing` in its OWN body (registering this view's
    /// observation of any observable state behind it) AND repaints on its
    /// own heartbeat (for probe-backed grants nothing observes) - so no
    /// parent can ever strand it stale. `GrantRow(grant)` is always live.
    ///
    /// DOCTRINE: action buttons carry NO hover tooltips - guidance a row
    /// needs is rendered INLINE as the standing's note, visible without
    /// hunting. Hover tips belong to dedicated info affordances.
    public struct GrantRow: View {
        private let grant: any Grant

        // The ONE presentation deferral, and only this one: a row must
        // never change at the moment its button is clicked. Clicking an
        // askable's action flips the probe to broken the instant the
        // prompt fires - rendering that live would sprout the denied
        // paragraph exactly as the user clicks (background mutation while
        // they navigate away reads as confusion, not help). So the
        // askable→broken transition HOLDS the askable presentation until
        // ARRIVAL (the row appears) or RETURN (the app regains focus with
        // the grant still missing) - the two moments more info is fair.
        // Every other transition renders IMMEDIATELY: grades on different
        // surfaces disagreeing is the split-brain this module bans.
        @State private var held: Standing?
        private let pulse = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

        public init(_ grant: any Grant) {
            self.grant = grant
        }

        public var body: some View {
            let live = grant.standing
            let shown = held ?? live
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: grant.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(grant.title).font(.callout.weight(.medium))
                    Text(grant.why)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = shown.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 12)
                if shown.grade == .good {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                } else {
                    Button(shown.actionTitle) { grant.act() }
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
            .onReceive(pulse) { _ in heartbeat = Date() }
            .onChange(of: live) { old, new in
                held = (old.grade == .askable && new.grade == .broken) ? old : nil
            }
            .onAppear { held = nil }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)
            ) { _ in held = nil }
        }

        // Unread by body on purpose: mutating it each pulse marks the view
        // dirty, so probe-backed standings re-derive once a second.
        @State private var heartbeat = Date()
    }
#endif
