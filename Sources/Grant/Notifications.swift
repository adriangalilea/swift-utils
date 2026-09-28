#if os(macOS)
    import AppKit
    import UserNotifications

    /// Whether the person SEES this app's notifications. "Authorized" alone
    /// lies: an app allowed with the alert style None, or delivered quietly
    /// (provisional), posts into Notification Center and interrupts nobody,
    /// which for a message that matters is the same as denied.
    public enum NotificationReach: String, Codable, Sendable {
        /// The system prompt has never been shown. One ask is available.
        case notAsked
        /// The person said no. macOS never prompts again; only System
        /// Settings can flip it.
        case denied
        /// Allowed, but nothing appears on screen: alerts off, alert style
        /// None, or quiet (provisional) delivery.
        case silenced
        /// Banners or alerts reach the screen.
        case allowed
    }

    /// The notification probe + request primitives, the `TCC` shape for the
    /// one permission that is not TCC's (usernoted owns it, per bundle).
    ///
    /// UNUserNotificationCenter only serves a BUNDLED app launched in the
    /// user's context (LaunchServices). A bare binary or a launchd agent
    /// cannot ask, read, or post; such a process hands its messages to a
    /// nested helper app and learns the reach from what the helper records.
    public enum Notifications {
        /// Synchronous, for the same 1 s pulse the TCC probes serve: the
        /// readout is one XPC round trip to usernoted. nil = no answer
        /// within `timeout`, or a status this build does not know, which
        /// `standing` renders as unknown rather than guessing.
        public static func reach(timeout: TimeInterval = 2) -> NotificationReach? {
            final class Answer: @unchecked Sendable { var reach: NotificationReach? }
            let answer = Answer()
            let done = DispatchSemaphore(value: 0)
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                answer.reach = reach(of: settings)
                done.signal()
            }
            guard done.wait(timeout: .now() + timeout) == .success else { return nil }
            return answer.reach
        }

        public static func reach(of settings: UNNotificationSettings) -> NotificationReach? {
            switch settings.authorizationStatus {
            case .notDetermined: .notAsked
            case .denied: .denied
            case .authorized:
                settings.alertSetting == .enabled && settings.alertStyle != .none
                    ? .allowed : .silenced
            case .provisional, .ephemeral: .silenced
            @unknown default: nil
            }
        }

        /// First ask fires the system prompt; after any answer macOS never
        /// prompts again, so asking again deep-links to this app's own row
        /// in System Settings › Notifications.
        public static func request(
            options: UNAuthorizationOptions = [.alert, .sound],
            bundleID: String = Bundle.main.bundleIdentifier!
        ) {
            guard reach() == .notAsked else { return openSettings(bundleID: bundleID) }
            UNUserNotificationCenter.current().requestAuthorization(options: options) { _, _ in }
        }

        /// System Settings › Notifications, scrolled to `bundleID`'s row. A
        /// helper app that posts on another process's behalf passes the
        /// HELPER's bundle id: the row belongs to whoever posts.
        public static func openSettings(bundleID: String) {
            NSWorkspace.shared.open(
                URL(
                    string:
                        "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)"
                )!)
        }

        /// The one derivation from reach to standing, shared by every app so
        /// no two of them disagree on what a silenced app means.
        public static func standing(_ reach: NotificationReach?) -> Standing {
            switch reach {
            case .allowed: .good
            case .notAsked: .askable("Allow\u{2026}")
            case .denied:
                .broken(
                    "Open Settings\u{2026}",
                    note: "Notifications are off in System Settings. macOS never asks twice.")
            case .silenced:
                .broken(
                    "Open Settings\u{2026}",
                    note:
                        "Allowed, but alerts are off: messages land in Notification Center without appearing."
                )
            case nil:
                .unknown(note: "Notification settings did not answer.")
            }
        }
    }

    /// The notification grant for an app that posts from its own process.
    /// The app supplies identity copy; reach, standing and action are the
    /// module's.
    public struct NotificationGrant: Grant {
        public let symbol: String
        public let title: String
        public let why: String
        public let required: Bool

        public init(
            symbol: String = "bell.badge", title: String = "Notifications", why: String,
            required: Bool = false
        ) {
            self.symbol = symbol
            self.title = title
            self.why = why
            self.required = required
        }

        public var standing: Standing { Notifications.standing(Notifications.reach()) }
        public func act() { Notifications.request() }
    }
#endif
