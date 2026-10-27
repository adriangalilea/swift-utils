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
                        .buttonStyle(.inkProminent)
                    }
                }
                .padding(20)
            }
        }

        /// One grant per page, on Ink's walk (`InkPages`: pages sliding the
        /// way walked, dots as markers, Back, ← → ⏎): its symbol large, its
        /// title and one line, and its action. The page moves on by itself the
        /// moment its grant is good; "Skip" passes an optional one, and a
        /// required one waits. An optional welcome page opens it; `onDone`
        /// runs after the last page.
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
                // The dots are a checklist: each grant's in its standing's
                // hue (green once allowed), and any of them a click away.
                InkPages(
                    page: $page, count: count, canAdvance: mayLeave, jump: .any,
                    marker: { index in
                        grant(index).map { grant in
                            let grade = grant.standing.grade
                            return grade == .good
                                ? .green : grade.needsUser ? PermissionGrant.hue(grade) : nil
                        } ?? nil
                    }
                ) { index in
                    if index < offset, let welcome {
                        welcome
                    } else {
                        Page(grants[index - offset])
                    }
                } action: { index in
                    action(index)
                }
                // On only when the grant turns good WHILE its page is shown:
                // arriving at one already good (Back onto it) is not that, and
                // moving on then bounced the walk forward from under the person.
                .onChange(of: Here(page: page, good: currentIsGood)) { before, now in
                    if now.page == before.page, now.good, !before.good { next() }
                }
            }

            private func grant(_ index: Int) -> PermissionGrant? {
                index >= offset ? grants[index - offset] : nil
            }
            private var currentIsGood: Bool { grant(page)?.standing.grade == .good }

            /// The page and whether its grant is good, watched together.
            private struct Here: Equatable {
                let page: Int
                let good: Bool
            }

            /// Forward past a page: a welcome, a grant that is good, one the
            /// app can't see, or an optional one; a required one waits.
            private func mayLeave(_ index: Int) -> Bool {
                guard let grant = grant(index) else { return true }
                return !grant.required || !grant.standing.grade.needsUser
            }

            /// The footer only walks: the grant's own ask is in its page,
            /// beside the words that explain it. ONE button, always there, one
            /// width, so a pointer resting on it (clicking through the walk)
            /// always lands on it: "Continue" ("Done" on the last) when
            /// nothing waits; "Skip" while an optional grant waits; a disabled
            /// "Continue" while a required one does (its page moves on by
            /// itself once it is good).
            @ViewBuilder private func action(_ index: Int) -> some View {
                let waiting = grant(index).map { $0.standing.grade.needsUser } ?? false
                let required = grant(index)?.required ?? false
                let words = index == count - 1 ? "Done" : "Continue"
                if waiting && !required {
                    Button {
                        next()
                    } label: {
                        footerLabel("Skip")
                    }.buttonStyle(.ink)
                } else {
                    Button {
                        next()
                    } label: {
                        footerLabel(words)
                    }
                    .buttonStyle(.inkProminent)
                    .keyboardShortcut(waiting ? nil : .defaultAction)
                    .disabled(waiting)
                }
            }

            /// Every footer word in one width: the button never resizes.
            private func footerLabel(_ words: String) -> some View {
                Text(letterCase.apply(words)).frame(minWidth: 74)
            }

            /// On a page; `InkPages` slides there (one path for every move).
            private func next() {
                guard page < count - 1 else { return onDone() }
                page += 1
            }
        }

        /// One grant, large: the page of `Steps`, usable alone. Its symbol,
        /// its title, why the app needs it and where it stands, and right
        /// under them its own action, large (⏎ presses it), or the status mark
        /// once it is good.
        public struct Page: View {
            let grant: PermissionGrant
            @Environment(\.permissionGrantCase) private var letterCase
            public init(_ grant: PermissionGrant) { self.grant = grant }

            public var body: some View {
                let standing = grant.standing
                VStack(spacing: 16) {
                    Image(systemName: grant.symbol)
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(grant.title).font(.title2.bold())
                    // The page asks, so it always says why; where the grant
                    // stands (the note) follows, smaller. A row has room for
                    // one of them; here the why was hidden behind "Off in
                    // Privacy & Security › …" exactly while it was needed
                    // (trash.app's Full Disk Access, 2026-10-27).
                    VStack(spacing: 6) {
                        Text(grant.why).foregroundStyle(.secondary)
                        if let note = standing.note {
                            Text(note).font(.callout).foregroundStyle(.tertiary)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    Group {
                        if standing.grade.needsUser {
                            GrantAction(hue: PermissionGrant.hue(standing.grade), fill: false) {
                                grant.act()
                            } label: { _ in
                                Text(letterCase.apply(standing.actionTitle))
                            }
                            .keyboardShortcut(.defaultAction)
                        } else {
                            GrantMark(grade: standing.grade)
                        }
                    }
                    .controlSize(.large)
                    .padding(.top, 8)
                }
                .onAppear { PermissionGrant.surfaceAppeared() }
            }
        }

        /// One element that is the warning AND its fix, there only while the
        /// grant needs the person (and truly nothing otherwise: no space, no
        /// gap in a stack): the grant action (`GrantAction`, the one control
        /// every surface draws) saying what is not working (`label`, "can't
        /// type into apps yet"; the grant's title when none is given).
        /// Hovered or focused, the same box says the fix ("open settings…")
        /// in its place; a click acts. Both texts hold the box's width, so
        /// hovering never moves anything. The resting words say it all: no
        /// tooltip.
        ///
        /// `fill`: the width the host gives it (a menu's full row, aligned with
        /// the controls above and below); otherwise it hugs its text. Its size
        /// follows `.controlSize` (`.small` for a dense line beside icons).
        public struct Chip: View {
            let grant: PermissionGrant
            let label: String?
            let fill: Bool
            @Environment(\.permissionGrantCase) private var letterCase

            public init(_ grant: PermissionGrant, label: String? = nil, fill: Bool = false) {
                self.grant = grant
                self.label = label
                self.fill = fill
            }

            public var body: some View {
                let standing = grant.standing
                if standing.grade.needsUser {
                    let what = label ?? grant.title
                    let fix = letterCase.apply(standing.actionTitle)
                    GrantAction(hue: PermissionGrant.hue(standing.grade), fill: fill) {
                        grant.act()
                    } label: { engaged in
                        ZStack(alignment: .leading) {
                            Text(what).opacity(engaged ? 0 : 1)
                            Text(fix).opacity(engaged ? 1 : 0)
                        }
                    }
                    .accessibilityLabel("\(what), \(fix)")
                    .onAppear { PermissionGrant.surfaceAppeared() }
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

                public init(_ label: String = "Open at login") { self.label = label }

                public var body: some View {
                    let standing = grant.standing
                    // Read with the standing it moves with: the standing is
                    // what is observed, so this never lags it.
                    let waiting =
                        if case .awaitingApproval = AppInstallation.Job.loginItem.state {
                            true
                        } else { false }
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
