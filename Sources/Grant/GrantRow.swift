#if os(macOS)
    import SwiftUI

    /// The one row every grant surface wears: icon, title + why, a live
    /// checkmark or the standing's action. SELF-SUFFICIENT by design, so a
    /// parent can never strand it stale: `GrantRow(grant)` is always live.
    /// Two update paths, both explicit - body reads `grant.standing`
    /// (registering this view's own observation of any observable state
    /// behind it, so claim-backed grants repaint the instant a verdict
    /// moves) and a 1s pulse re-probes (for probe-backed grants nothing
    /// observes).
    ///
    /// DOCTRINE: action buttons carry NO hover tooltips - guidance a row
    /// needs is rendered INLINE as the standing's note, visible without
    /// hunting. Hover tips belong to dedicated info affordances.
    public struct GrantRow: View {
        private let grant: any Grant

        // What the row currently shows. Nearly always the live standing -
        // sync() copies it over on every signal - EXCEPT the one
        // presentation deferral: a row must never change at the moment its
        // button is clicked. Clicking an askable's action flips the probe
        // to broken the instant the prompt fires, and rendering that live
        // would sprout the denied paragraph exactly as the user clicks
        // (background mutation while they navigate away reads as
        // confusion, not help). So askable→broken HOLDS until ARRIVAL
        // (the row appears) or RETURN (the app regains focus with the
        // grant still missing) - the two moments more info is fair. Every
        // other transition renders immediately: grades on different
        // surfaces disagreeing is the split-brain this module bans.
        @State private var shown: Standing?
        private let pulse = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

        public init(_ grant: any Grant) {
            self.grant = grant
        }

        public var body: some View {
            let live = grant.standing
            let standing = shown ?? live
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
                    if let note = standing.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 12)
                if standing.grade == .good {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                } else {
                    Button(standing.actionTitle) { grant.act() }
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
            .onChange(of: live) { sync() }
            .onReceive(pulse) { _ in sync() }
            .onAppear { sync(arrival: true) }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)
            ) { _ in sync(arrival: true) }
        }

        private func sync(arrival: Bool = false) {
            let live = grant.standing
            if !arrival, shown?.grade == .askable, live.grade == .broken { return }
            if shown != live { shown = live }
        }
    }
#endif
