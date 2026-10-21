#if os(macOS) || os(iOS)
    import SwiftUI
    #if os(macOS)
        import AppKit
    #endif

    // The shapes a list of grants takes, each composed from the same grants
    // and none forced: an app picks the one that fits the moment.
    //
    //     PermissionGrant.Section("Permissions", grants)            // a Settings section
    //     PermissionGrant.Sheet(title: "quick setup", grants) { … } // everything on one sheet (hollow)
    //     PermissionGrant.Steps(grants, welcome: { … }) { … }       // one grant per page (steno)
    //     PermissionGrant.Chip(.microphone)                         // inline, only while it needs the person
    //
    // Every one reads each grant's live standing (the Privacy hub publishes
    // changes at once; a 1 s pulse catches what nothing announces, a
    // background service's approval) and renders it mechanically: no surface
    // re-derives "is this a problem?", no surface shows a loading state or a
    // guess.

    /// Re-renders its content every second: the read of what no system
    /// announces (SMAppService's approval, a notification setting).
    private struct Live<Content: View>: View {
        @ViewBuilder let content: () -> Content
        var body: some View {
            TimelineView(.periodic(from: .now, by: 1)) { _ in content() }
        }
    }

    extension PermissionGrant {
        /// A Settings section: an optional title, a row per grant, an optional
        /// footer. Required grants first.
        public struct Section: View {
            let title: String?
            let grants: [PermissionGrant]
            let footer: String?

            public init(_ title: String?, _ grants: [PermissionGrant], footer: String? = nil) {
                self.title = title
                self.grants = grants.sorted { $0.required && !$1.required }
                self.footer = footer
            }

            /// Untitled, inside a host's own section (a Form's `Section`).
            public init(_ grants: [PermissionGrant], footer: String? = nil) {
                self.init(nil, grants, footer: footer)
            }

            public var body: some View {
                VStack(alignment: .leading, spacing: 6) {
                    if let title {
                        Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(Array(grants.enumerated()), id: \.offset) { _, grant in Row(grant) }
                    if let footer {
                        Text(footer).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        /// Everything on one sheet: the app's icon and a line, the required
        /// grants, the optional ones with what the app does without them, and
        /// one button that says "later" while a required grant still needs
        /// the person, "done" once none does.
        public struct Sheet: View {
            let title: String
            let subtitle: String?
            let grants: [PermissionGrant]
            let optionalNote: String?
            let onDone: () -> Void

            public init(
                title: String, subtitle: String? = nil, _ grants: [PermissionGrant],
                optionalNote: String? = nil,
                onDone: @escaping () -> Void
            ) {
                self.title = title
                self.subtitle = subtitle
                self.grants = grants
                self.optionalNote = optionalNote
                self.onDone = onDone
            }

            public var body: some View {
                Live {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            AppIcon(size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(.headline)
                                if let subtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        let required = grants.filter(\.required)
                        let optional = grants.filter { !$0.required }
                        if !required.isEmpty { Section("required", required) }
                        if !optional.isEmpty {
                            Section("optional", optional, footer: optionalNote)
                        }
                        HStack {
                            Spacer()
                            Button(
                                required.contains { $0.standing.grade.needsUser } ? "later" : "done"
                            ) {
                                onDone()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(20)
                }
            }
        }

        /// One grant per page: its symbol large, its title and one line, and
        /// its action. The page moves on by itself the moment its grant is
        /// good; "skip" passes an optional one, and a required one waits. An
        /// optional welcome page opens it; `onDone` runs after the last page.
        public struct Steps<Welcome: View>: View {
            let grants: [PermissionGrant]
            let welcome: Welcome?
            let onDone: () -> Void
            @State private var page = 0

            public init(
                _ grants: [PermissionGrant], @ViewBuilder welcome: () -> Welcome,
                onDone: @escaping () -> Void
            ) {
                self.grants = grants
                self.welcome = welcome()
                self.onDone = onDone
            }

            private var offset: Int { welcome == nil ? 0 : 1 }
            private var count: Int { grants.count + offset }

            public var body: some View {
                Live {
                    VStack(spacing: 0) {
                        Group {
                            if page < offset, let welcome {
                                welcome
                            } else {
                                Page(grants[page - offset])
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(32)
                        Divider()
                        footer.padding(16)
                    }
                    .onChange(of: currentIsGood) { _, good in if good { next() } }
                }
            }

            private var current: PermissionGrant? { page >= offset ? grants[page - offset] : nil }
            private var currentIsGood: Bool { current?.standing.grade == .good }

            @ViewBuilder private var footer: some View {
                HStack {
                    Text("\(page + 1) of \(count)").font(.caption.monospaced()).foregroundStyle(
                        .tertiary)
                    Spacer()
                    if let current, !current.required, current.standing.grade != .good {
                        Button("skip") { next() }
                    }
                    if let current, current.standing.grade.needsUser {
                        Button(current.standing.actionTitle) { current.act() }
                            .keyboardShortcut(.defaultAction)
                    } else if current == nil || current?.standing.grade == .good
                        || current?.standing.grade == .unknown
                    {
                        Button(page == count - 1 ? "done" : "continue") { next() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }

            private func next() {
                if page >= count - 1 { onDone() } else { page += 1 }
            }
        }

        /// One grant, large: the page of `Steps`, usable alone.
        public struct Page: View {
            let grant: PermissionGrant
            public init(_ grant: PermissionGrant) { self.grant = grant }

            public var body: some View {
                let standing = grant.standing
                VStack(spacing: 16) {
                    Image(
                        systemName: standing.grade == .good ? "checkmark.circle.fill" : grant.symbol
                    )
                    .font(.system(size: 48))
                    .foregroundStyle(
                        standing.grade == .good ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    Text(grant.title).font(.title2.bold())
                    // Two texts, as a row: the note when there is one, else why.
                    Text(standing.note ?? grant.why)
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(
                            maxWidth: 360)
                }
            }
        }

        /// Inline, only while the grant needs the person: its action as a
        /// small button with the note beside it. Nothing at all when good.
        public struct Chip: View {
            let grant: PermissionGrant
            public init(_ grant: PermissionGrant) { self.grant = grant }

            public var body: some View {
                Live {
                    let standing = grant.standing
                    if standing.grade.needsUser {
                        HStack(spacing: 6) {
                            // A button alone never says what it is for: the
                            // note, or else the grant's own name.
                            Text(standing.note ?? grant.title).font(.caption).foregroundStyle(
                                .secondary
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            Button(standing.actionTitle) { grant.act() }.controlSize(.small)
                        }
                    }
                }
            }
        }

        #if os(macOS)
            /// "Open at login" as the choice it is (never a requirement): the
            /// app's login item, read live, with the approval note when macOS
            /// holds it for the person.
            public struct LaunchAtLogin: View {
                let label: String
                private let grant = PermissionGrant.backgroundService(
                    .loginItem, title: "open at login", why: "", required: false)
                private var waiting: Bool {
                    BackgroundService.loginItem.service.status == .requiresApproval
                }

                public init(_ label: String = "Open at login") { self.label = label }

                public var body: some View {
                    Live {
                        let standing = grant.standing
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle(
                                label,
                                isOn: Binding(
                                    get: { standing.grade == .good || waiting },
                                    set: { on in on ? grant.act() : grant.unregister() }))
                            if waiting, let note = standing.note {
                                Button(note) { grant.act() }.buttonStyle(.link).font(.caption)
                            }
                        }
                    }
                }
            }
        #endif
    }

    /// The app's own icon, where a surface introduces the app.
    private struct AppIcon: View {
        let size: CGFloat
        var body: some View {
            #if os(macOS)
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: size, height: size)
            #else
                EmptyView()
            #endif
        }
    }

    extension PermissionGrant.Steps where Welcome == EmptyView {
        public init(_ grants: [PermissionGrant], onDone: @escaping () -> Void) {
            self.grants = grants
            self.welcome = nil
            self.onDone = onDone
        }
    }
#endif
