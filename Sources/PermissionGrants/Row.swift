#if os(macOS) || os(iOS) || os(watchOS)
    import SwiftUI
    private let becameActive = Platform.becameActive

    extension PermissionGrant {
        /// The one row every grant surface wears: icon, title and one line
        /// under it, a live checkmark or the standing's action. SELF-SUFFICIENT
        /// by design, so a parent can never strand it stale: `Row(grant)` is
        /// always live: body reads `grant.standing`, which is observable for
        /// every kind, so the row repaints the instant what it shows moves and
        /// never otherwise. Appearing, it asks for a fresh read.
        ///
        /// DOCTRINE: action buttons carry NO hover tooltips: guidance a row
        /// needs is rendered INLINE as the standing's note, visible without
        /// hunting.
        public struct Row: View {
            private let grant: PermissionGrant

            // What the row currently shows. Nearly always the live standing
            // (sync() copies it over on every signal) EXCEPT the one
            // presentation deferral: a row must never change at the moment
            // its button is clicked. Clicking an askable's action can flip it
            // to broken the instant the prompt fires, and rendering that live
            // sprouts the denied note exactly as the person clicks. So
            // askable→broken HOLDS until ARRIVAL (the row appears) or RETURN
            // (the app regains focus with the grant still missing). Every
            // other transition renders immediately.
            @State private var shown: Standing?
            @Environment(\.permissionGrantCase) private var letterCase

            /// `row`: a settings list line (small icon, title and one line, a
            /// small control). `card`: a device-list card (a large icon tinted
            /// by the standing, title over one line, the mark or the action on
            /// the right).
            public enum Style: Sendable { case row, card }
            private let style: Style

            public init(_ grant: PermissionGrant, style: Style = .row) {
                self.grant = grant
                self.style = style
            }

            public var body: some View {
                let live = grant.standing
                let standing = shown ?? live
                content(standing)
                    .onChange(of: live) { sync() }
                    .onAppear {
                        PermissionGrant.surfaceAppeared()
                        sync(arrival: true)
                    }
                    // Back from Settings (where the person changes it) is RETURN.
                    .onReceive(NotificationCenter.default.publisher(for: becameActive)) { _ in
                        sync(arrival: true)
                    }
            }

            @ViewBuilder private func content(_ standing: Standing) -> some View {
                #if os(watchOS)
                    // A watch is too narrow for anything side by side: one column, the action full width.
                    stacked(standing)
                #else
                    switch style {
                    case .row: row(standing)
                    case .card: card(standing)
                    }
                #endif
            }

            private func stacked(_ standing: Standing) -> some View {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(grant.title).font(.headline)
                    } icon: {
                        Image(systemName: grant.symbol).foregroundStyle(tint(standing.grade))
                    }
                    Text(standing.note ?? grant.why)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    switch standing.grade {
                    case .good, .unknown:
                        GrantMark(grade: standing.grade)
                    case .askable, .broken:
                        GrantAction(hue: PermissionGrant.hue(standing.grade), fill: true) {
                            grant.act()
                        } label: { _ in
                            Text(letterCase.apply(standing.actionTitle))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    trailing(standing)
                }
            }

            /// The one trailing element, in the actions' shape for every
            /// standing: the action while it needs the person; the same pill
            /// with a mark when it does not (a check, or the honest "unknown":
            /// the app can't see it, so it neither vouches nor warns).
            @ViewBuilder private func trailing(_ standing: Standing) -> some View {
                switch standing.grade {
                case .good, .unknown:
                    GrantMark(grade: standing.grade)
                case .askable, .broken:
                    GrantAction(hue: PermissionGrant.hue(standing.grade), fill: false) {
                        grant.act()
                    } label: { _ in
                        Text(letterCase.apply(standing.actionTitle))
                    }
                }
            }

            /// The icon says the standing at a glance, as a device row does:
            /// green when good, the action's own hue while it needs the person.
            private func tint(_ grade: Standing.Grade) -> Color {
                switch grade {
                case .good: .green
                case .askable, .broken: PermissionGrant.hue(grade)
                case .unknown: .secondary
                }
            }

            private func row(_ standing: Standing) -> some View {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: grant.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                        .padding(.top, 1)
                    // Two lines, never three: what it is, and one short line
                    // under it. The standing's note, when there is one, IS that
                    // line (it says what to do now); the why otherwise.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(grant.title).font(.callout.weight(.medium))
                        Text(standing.note ?? grant.why)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    trailing(standing)
                }
                .padding(.vertical, 4)
            }

            private func sync(arrival: Bool = false) {
                let live = grant.standing
                if !arrival, shown?.grade == .askable, live.grade == .broken { return }
                if shown != live { shown = live }
            }
        }
    }
#endif
