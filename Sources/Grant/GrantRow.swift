#if os(macOS) || os(iOS)
    import Combine
    import SwiftUI
    #if os(macOS)
        import AppKit
        private let becameActive = NSApplication.didBecomeActiveNotification
    #else
        import UIKit
        private let becameActive = UIApplication.didBecomeActiveNotification
    #endif

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

        /// `row`: a settings list line (small icon, why + note, a small
        /// control). `card`: a device-list card, the shape of a row of
        /// devices on a phone (a large icon tinted by the standing, title
        /// over one line of detail, the mark or the action centred on the
        /// right); the detail is the note when there is one, else the why.
        public enum Style: Sendable { case row, card }
        private let style: Style

        public init(_ grant: any Grant, style: Style = .row) {
            self.grant = grant
            self.style = style
        }

        public var body: some View {
            let live = grant.standing
            let standing = shown ?? live
            content(standing)
                .onChange(of: live) { sync() }
                .onReceive(pulse) { _ in sync() }
                .onAppear { sync(arrival: true) }
                // Back from Settings (where the person changes it) is RETURN.
                .onReceive(NotificationCenter.default.publisher(for: becameActive)) { _ in
                    sync(arrival: true)
                }
        }

        @ViewBuilder private func content(_ standing: Standing) -> some View {
            switch style {
            case .row: row(standing)
            case .card: card(standing)
            }
        }

        private func card(_ standing: Standing) -> some View {
            HStack(spacing: 14) {
                Image(systemName: grant.symbol)
                    .font(.title2)
                    .foregroundStyle(tint(standing.grade))
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(grant.title).font(.body.weight(.medium))
                    Text(standing.note ?? grant.why)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                switch standing.grade {
                case .good:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.green)
                case .unknown:
                    Text("unknown")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                case .askable, .broken:
                    Button(standing.actionTitle) { grant.act() }
                        .buttonStyle(.glassProminent)
                }
            }
        }

        /// The icon says the standing at a glance, as a device row does:
        /// green when good, orange when the person must fix it.
        private func tint(_ grade: Standing.Grade) -> Color {
            switch grade {
            case .good: .green
            case .broken: .orange
            case .askable, .unknown: .secondary
            }
        }

        private func row(_ standing: Standing) -> some View {
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
                switch standing.grade {
                case .good:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                case .unknown:
                    // The honest mark: the app can't see this grant, so it
                    // neither vouches (a checkmark) nor warns (a button).
                    Text("unknown")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.top, 3)
                case .askable, .broken:
                    Button(standing.actionTitle) { grant.act() }
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }

        private func sync(arrival: Bool = false) {
            let live = grant.standing
            if !arrival, shown?.grade == .askable, live.grade == .broken { return }
            if shown != live { shown = live }
        }
    }
#endif
