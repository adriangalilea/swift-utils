import Foundation

#if os(macOS) || os(iOS)
    import UserNotifications
#endif

/// One thing the app needs the person, or macOS, to allow: a Privacy &
/// Security switch, a background service, notifications, or anything of the
/// app's own. The app declares each ONCE, as a named constant, and that one
/// name is every screen's row and every line of code's gate, ask and hook:
///
///     extension PermissionGrant {
///         static let microphone = PermissionGrant.privacy(
///             .microphone, title: "Microphone", why: "Records your side of the call.")
///     }
///     PermissionGrant.Section("Permissions", [.microphone])   // a screen
///     guard await PermissionGrant.microphone.ask() else { … } // code
///
/// The module's one top-level name: everything else is nested here, so no
/// app's own `Grant`, `Permission`, `Standing` or `Claim` can collide.
public struct PermissionGrant: Sendable {
    public enum Kind: Sendable {
        #if os(macOS)
            /// A switch in System Settings › Privacy & Security.
            case privacy(Privacy)
            /// Privacy & Security › Automation: Apple Events to one app.
            case automation(bundleID: String)
            /// A process run beside the app through `SMAppService`.
            case backgroundService(BackgroundService)
        #endif
        #if os(macOS) || os(iOS)
            /// Notifications posted from the app's own process.
            case notifications(UNAuthorizationOptions)
        #endif
        /// The app's own: what it reads, and what the button does. Both run on
        /// the main thread (they read the app's own state).
        case custom(
            standing: @MainActor @Sendable () -> Standing, act: @MainActor @Sendable () -> Void)
    }

    public let kind: Kind
    public let title: String
    /// Why the app needs it, one short line under the title.
    public let why: String
    public let symbol: String
    /// Required gates a feature; optional only enriches one. Drives
    /// `blocking` and how the shapes group the rows.
    public let required: Bool

    /// The app's own grant.
    public init(
        title: String, why: String, symbol: String, required: Bool = true,
        standing: @escaping @MainActor @Sendable () -> Standing,
        act: @escaping @MainActor @Sendable () -> Void
    ) {
        self.init(
            kind: .custom(standing: standing, act: act), title: title, why: why, symbol: symbol,
            required: required)
    }

    init(kind: Kind, title: String, why: String, symbol: String, required: Bool) {
        self.kind = kind
        self.title = title
        self.why = why
        self.symbol = symbol
        self.required = required
    }

    #if os(macOS)
        public static func privacy(
            _ privacy: Privacy, title: String, why: String, symbol: String? = nil,
            required: Bool = true
        ) -> PermissionGrant {
            PermissionGrant(
                kind: .privacy(privacy), title: title, why: why, symbol: symbol ?? privacy.symbol,
                required: required)
        }

        public static func automation(
            of bundleID: String, title: String, why: String, symbol: String = "applescript",
            required: Bool = true
        ) -> PermissionGrant {
            PermissionGrant(
                kind: .automation(bundleID: bundleID), title: title, why: why, symbol: symbol,
                required: required)
        }

        public static func backgroundService(
            _ service: BackgroundService, title: String, why: String,
            symbol: String = "gearshape.2", required: Bool = true
        ) -> PermissionGrant {
            PermissionGrant(
                kind: .backgroundService(service), title: title, why: why, symbol: symbol,
                required: required)
        }
    #endif

    #if os(macOS) || os(iOS)
        public static func notifications(
            title: String = "Notifications", why: String, symbol: String = "bell.badge",
            required: Bool = false, options: UNAuthorizationOptions = [.alert, .sound]
        ) -> PermissionGrant {
            PermissionGrant(
                kind: .notifications(options), title: title, why: why, symbol: symbol,
                required: required)
        }
    #endif

    // MARK: Reading

    /// What every surface renders: the one place a raw status becomes
    /// presentation. Observable for every kind (a view or hook that reads it
    /// is told when it changes): a Privacy switch through the hub, the kinds
    /// macOS does not announce through `Readings`, the app's own through the
    /// state its closure reads.
    public var standing: Standing {
        switch kind {
        #if os(macOS)
            case .privacy(let privacy): PrivacyHub.shared.standing(privacy)
            case .automation(let bundleID):
                Readings.shared.standing("automation \(bundleID)") {
                    Automation.standing(of: bundleID)
                }
            case .backgroundService(let service):
                Readings.shared.standing("background service \(service)") { [title] in
                    service.standing(title: title)
                }
        #endif
        #if os(macOS) || os(iOS)
            case .notifications:
                Readings.shared.standing("notifications") {
                    Notifications.standing(Notifications.reach())
                }
        #endif
        case .custom(let standing, _): MainActor.assumeIsolated { standing() }
        }
    }

    /// The gate: the app may do what this grant is for, right now.
    public var isAllowed: Bool { standing.grade == .good }

    /// THE banner/preflight predicate: a required grant the person must fix.
    /// Optional grants never block anything.
    public var blocking: Bool { required && standing.grade == .broken }

    // MARK: Asking

    /// The standing's button: asks, opens the right Settings, or reopens.
    @MainActor public func act() {
        Task { _ = await ask() }
    }

    /// Asks the way this grant asks (the prompt, Settings, Login Items, a
    /// reopen) and answers whether it is allowed once the person answered.
    /// Where macOS answers in System Settings instead of a prompt, it returns
    /// at once; `observe` reports the switch when it flips.
    @discardableResult
    @MainActor public func ask() async -> Bool {
        switch kind {
        #if os(macOS)
            case .privacy(let privacy): await PrivacyHub.shared.ask(privacy)
            case .automation(let bundleID): await Automation.ask(bundleID)
            case .backgroundService(let service): service.act(title: title)
        #endif
        #if os(macOS) || os(iOS)
            case .notifications(let options): await Notifications.ask(options: options)
        #endif
        case .custom(_, let act): act()
        }
        // What the ask changed (a registration, a prompt's answer) shows now.
        Readings.shared.readAll()
        return isAllowed
    }

    #if os(macOS)
        /// Turns a background service off (a login item the person
        /// unchecks): the reverse of `ask`, idempotent. Only a background
        /// service can be withdrawn by the app.
        public func unregister() {
            guard case .backgroundService(let service) = kind else {
                preconditionFailure("\(title): only a background service unregisters")
            }
            service.unregister(title: title)
        }

        /// First thing in an app's `main`: a launch as the hub's fresh probe
        /// answers and exits. Without it a Privacy & Security change shows
        /// only when the app reopens.
        public static func answerProbeIfAsked() { PrivacyHub.answerProbeIfAsked() }
    #endif
}

extension PermissionGrant {
    /// The ONE user-facing answer for a grant, presentation riding the state.
    ///
    /// THE LAW this type exists to enforce: a surface renders a Standing
    /// mechanically (grade → checkmark or button, `actionTitle` on the button,
    /// `note` under the title) and NEVER re-derives "is this a problem?" from
    /// anything rawer. Two surfaces answering that question with their own
    /// thresholds is the split-brain bug, and with Standing as the only
    /// readable vocabulary it is unwritable. An enum so the invalid states (a
    /// good with an action, a broken without its fix) are unrepresentable.
    public enum Standing: Equatable, Sendable {
        /// Granted, and the app can SEE that it is. Checkmark; no surface
        /// warns, no banner, no note.
        case good
        /// Not yet granted, one click asks. An OFFER, never a failure:
        /// onboarding and settings present it, nothing warns about it.
        case askable(_ actionTitle: String, note: String? = nil)
        /// The person must fix something outside the app. EVERY surface warns
        /// with this same note and action.
        case broken(_ actionTitle: String, note: String)
        /// The app CANNOT READ whether this is granted, and nothing has
        /// contradicted it: a quiet "unknown", no checkmark, no button, the
        /// note saying why. Never warns, never blocks, never asks.
        case unknown(note: String)

        /// The payload-free shape, for the comparisons surfaces live on
        /// (`grade == .broken`, `grade.needsUser`).
        public enum Grade: Equatable, Sendable {
            case good, askable, broken, unknown

            /// Something for the person to DO: ask, or fix.
            public var needsUser: Bool { self == .askable || self == .broken }
        }

        public var grade: Grade {
            switch self {
            case .good: .good
            case .askable: .askable
            case .broken: .broken
            case .unknown: .unknown
            }
        }

        /// Rendered only for the grades with a button (`askable`, `broken`).
        public var actionTitle: String {
            switch self {
            case .good, .unknown: ""
            case .askable(let title, _), .broken(let title, note: _): title
            }
        }

        public var note: String? {
            switch self {
            case .good: nil
            case .askable(_, let note): note
            case .broken(_, let note): note
            case .unknown(let note): note
            }
        }
    }
}
