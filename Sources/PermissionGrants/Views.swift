#if os(macOS) || os(iOS)
    import Ink
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
    //     PermissionGrant.Chip(.typing, label: "can't type yet")    // the warning that is its own fix
    //
    // Every one reads each grant's standing, which is observable for every
    // kind: a view repaints when what it read changes, and never otherwise (no
    // timer, no loading state, no guess). Appearing, a surface asks for the
    // facts to be read fresh (`surfaceAppeared`). Each renders the standing
    // mechanically: no surface re-derives "is this a problem?".

    extension PermissionGrant {
        /// How a surface cases the words this library writes on buttons and
        /// headings ("Open Settings…", "Later", "Required"): macOS's Title
        /// Case, or an app's lowercase voice. Set once on a host
        /// (`.permissionGrantCase(.lower)`); notes are sentences and keep
        /// their case.
        public enum LetterCase: Sendable {
            case title, lower

            public func apply(_ words: String) -> String {
                self == .lower ? words.lowercased() : words
            }
        }
    }

    extension EnvironmentValues {
        @Entry public var permissionGrantCase: PermissionGrant.LetterCase = .title
    }

    extension View {
        /// The case of every grant word drawn inside (`PermissionGrant.LetterCase`).
        public func permissionGrantCase(_ letterCase: PermissionGrant.LetterCase) -> some View {
            environment(\.permissionGrantCase, letterCase)
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
        /// one button that says "Later" while a required grant still needs
        /// the person, "Done" once none does.
        public struct Sheet: View {
            let title: String
            let subtitle: String?
            let grants: [PermissionGrant]
            let optionalNote: String?
            let onDone: () -> Void
            @Environment(\.permissionGrantCase) private var letterCase

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
                let required = grants.filter(\.required)
                let optional = grants.filter { !$0.required }
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
                    if !required.isEmpty { Section(letterCase.apply("Required"), required) }
                    if !optional.isEmpty {
                        Section(letterCase.apply("Optional"), optional, footer: optionalNote)
                    }
                    HStack {
                        Spacer()
                        Button(
                            letterCase.apply(
                                required.contains { $0.standing.grade.needsUser } ? "Later" : "Done"
                            )
                        ) { onDone() }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
            }
        }

        /// One grant per page: its symbol large, its title and one line, and
        /// its action. The page moves on by itself the moment its grant is
        /// good; "Skip" passes an optional one, and a required one waits. An
        /// optional welcome page opens it; `onDone` runs after the last page.
        public struct Steps<Welcome: View>: View {
            let grants: [PermissionGrant]
            let welcome: Welcome?
            let onDone: () -> Void
            @State private var page = 0
            @Environment(\.permissionGrantCase) private var letterCase

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

            private var current: PermissionGrant? { page >= offset ? grants[page - offset] : nil }
            private var currentIsGood: Bool { current?.standing.grade == .good }

            @ViewBuilder private var footer: some View {
                HStack {
                    Text("\(page + 1) of \(count)").font(.caption.monospaced()).foregroundStyle(
                        .tertiary)
                    Spacer()
                    if let current, !current.required, current.standing.grade != .good {
                        Button(letterCase.apply("Skip")) { next() }
                    }
                    if let current, current.standing.grade.needsUser {
                        Button(letterCase.apply(current.standing.actionTitle)) { current.act() }
                            .keyboardShortcut(.defaultAction)
                    } else if current == nil || current?.standing.grade == .good
                        || current?.standing.grade == .unknown
                    {
                        Button(letterCase.apply(page == count - 1 ? "Done" : "Continue")) {
                            next()
                        }
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
                .onAppear { PermissionGrant.surfaceAppeared() }
            }
        }

        /// One element that is the warning AND its fix, there only while the
        /// grant needs the person (and truly nothing otherwise: no space, no
        /// gap in a stack): a dot in the standing's hue and what is not
        /// working (`label`, "can't type into apps yet"; the grant's title when
        /// none is given). Hovered or focused, the same box says the fix
        /// ("open settings…") in the label's place, the note as its Ink tip; a
        /// click acts. Both texts hold the box's width, so hovering never
        /// moves anything.
        ///
        /// `fill`: the width the host gives it (a menu's full row, aligned with
        /// the controls above and below); otherwise it hugs its text.
        public struct Chip: View {
            let grant: PermissionGrant
            let label: String?
            let fill: Bool
            @Environment(\.permissionGrantCase) private var letterCase
            @State private var hovering = false
            @FocusState private var focused: Bool

            public init(_ grant: PermissionGrant, label: String? = nil, fill: Bool = false) {
                self.grant = grant
                self.label = label
                self.fill = fill
            }

            public var body: some View {
                let standing = grant.standing
                if standing.grade.needsUser {
                    let fixing = hovering || focused
                    let what = label ?? grant.title
                    let fix = letterCase.apply(standing.actionTitle)
                    Button {
                        grant.act()
                    } label: {
                        HStack(spacing: 7) {
                            Circle().fill(Self.hue(standing.grade)).frame(width: 6, height: 6)
                            ZStack(alignment: .leading) {
                                Text(what).opacity(fixing ? 0 : 1)
                                Text(fix).opacity(fixing ? 1 : 0)
                            }
                            .lineLimit(1)
                        }
                        .font(.system(size: 11.5))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(.primary.opacity(fixing ? 0.11 : 0.06))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .focused($focused)
                    .onHover { hovering = $0 }
                    .animation(.easeOut(duration: 0.12), value: fixing)
                    .inkTip(standing.note ?? grant.why, tint: Self.hue(standing.grade))
                    .accessibilityLabel("\(what), \(fix)")
                    .onAppear { PermissionGrant.surfaceAppeared() }
                }
            }

            /// Something to fix is orange; an offer the person has not
            /// answered yet is the quieter yellow.
            static func hue(_ grade: Standing.Grade) -> Color {
                grade == .broken ? .orange : .yellow
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

                public init(_ label: String = "Open at login") { self.label = label }

                public var body: some View {
                    let standing = grant.standing
                    // Read with the standing it moves with: the standing is
                    // what is observed, so this never lags it.
                    let waiting = BackgroundService.loginItem.service.status == .requiresApproval
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
                    .onAppear { PermissionGrant.surfaceAppeared() }
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
