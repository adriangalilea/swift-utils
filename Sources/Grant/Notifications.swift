#if os(macOS) || os(iOS)
    import UserNotifications
    #if os(macOS)
        import AppKit
    #else
        import UIKit
    #endif

    /// Whether the person SEES this app's notifications. "Authorized" alone
    /// lies: an app allowed with every on-screen delivery off, or delivered
    /// quietly (provisional), posts into a list and interrupts nobody, which
    /// for a message that matters is the same as denied.
    public enum NotificationReach: String, Codable, Sendable {
        /// The system prompt has never been shown. One ask is available.
        case notAsked
        /// The person said no. The system never prompts again; only
        /// Settings can flip it.
        case denied
        /// Allowed, but nothing appears where the person looks: alerts off
        /// (macOS: alert style None; iOS: banners and Lock Screen both off),
        /// or quiet (provisional) delivery.
        case silenced
        /// Banners or alerts reach the screen.
        case allowed
    }

    /// The notification probe + request primitives, the `TCC` shape for the
    /// one permission that is not TCC's (the notification daemon owns it,
    /// per bundle).
    ///
    /// The reach is a FACT the person changes in Settings at any moment,
    /// never a value an app keeps: every surface reads it fresh (`GrantRow`
    /// re-probes on activation and on a pulse). An app that asked once at
    /// launch and remembered the answer shows "off" after the person turned
    /// it on.
    ///
    /// macOS: UNUserNotificationCenter only serves a BUNDLED app launched in
    /// the user's context (LaunchServices). A bare binary or a launchd agent
    /// cannot ask, read, or post; such a process hands its messages to a
    /// nested helper app and learns the reach from what the helper records.
    public enum Notifications {
        /// Synchronous, for the same 1 s pulse the TCC probes serve: the
        /// readout is one XPC round trip (the answer arrives off the main
        /// queue). nil = no answer within `timeout`, or a status this build
        /// does not know, which `standing` renders as unknown.
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

        /// The same readout without blocking, for code already async.
        public static func reach() async -> NotificationReach? {
            reach(of: await UNUserNotificationCenter.current().notificationSettings())
        }

        public static func reach(of settings: UNNotificationSettings) -> NotificationReach? {
            switch settings.authorizationStatus {
            case .notDetermined: .notAsked
            case .denied: .denied
            case .authorized: seen(settings) ? .allowed : .silenced
            case .provisional, .ephemeral: .silenced
            @unknown default: nil
            }
        }

        /// What "on screen" means per platform. macOS: an alert style that
        /// draws something. iOS: a banner while the phone is in use, or the
        /// Lock Screen while it is not (a phone in a pocket is reached there).
        private static func seen(_ settings: UNNotificationSettings) -> Bool {
            #if os(macOS)
                settings.alertSetting == .enabled && settings.alertStyle != .none
            #else
                settings.alertSetting == .enabled || settings.lockScreenSetting == .enabled
            #endif
        }

        /// First ask fires the system prompt; after any answer the system
        /// never prompts again, so asking again opens this app's own
        /// notification settings.
        public static func request(
            options: UNAuthorizationOptions = [.alert, .sound],
            bundleID: String = Bundle.main.bundleIdentifier!
        ) {
            Task {
                guard await reach() == .notAsked else { return openSettings(bundleID: bundleID) }
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: options)
            }
        }

        /// The app's notification settings. macOS: System Settings ›
        /// Notifications scrolled to `bundleID`'s row (a helper app that
        /// posts on another process's behalf passes the HELPER's id: the row
        /// belongs to whoever posts). iOS: Settings › this app › Notifications
        /// (only ever the calling app's own; `bundleID` is not used).
        public static func openSettings(bundleID: String) {
            #if os(macOS)
                NSWorkspace.shared.open(
                    URL(
                        string:
                            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)"
                    )!)
            #else
                Task { @MainActor in
                    UIApplication.shared.open(URL(string: UIApplication.openNotificationSettingsURLString)!)
                }
            #endif
        }

        #if os(macOS)
            static let settingsName = "System Settings"
            static let system = "macOS"
            static let silencedNote =
                "Allowed, but alerts are off: messages land in Notification Center without appearing."
        #else
            static let settingsName = "Settings"
            static let system = "iOS"
            static let silencedNote =
                "Allowed, but banners and the Lock Screen are both off: messages land in Notification Centre without appearing."
        #endif

        /// The one derivation from reach to standing, shared by every app so
        /// no two of them disagree on what a silenced app means.
        public static func standing(_ reach: NotificationReach?) -> Standing {
            switch reach {
            case .allowed: .good
            case .notAsked: .askable("Allow\u{2026}")
            case .denied:
                .broken(
                    "Open \(settingsName)\u{2026}",
                    note: "Notifications are off in \(settingsName). \(system) never asks twice.")
            case .silenced:
                .broken("Open \(settingsName)\u{2026}", note: silencedNote)
            case nil:
                .unknown(note: "Notification settings did not answer.")
            }
        }
    }

    /// The notification grant for an app that posts from its own process
    /// (iOS: and receives remote notifications). The app supplies identity
    /// copy; reach, standing and action are the module's.
    public struct NotificationGrant: Grant {
        public let symbol: String
        public let title: String
        public let why: String
        public let required: Bool
        public let options: UNAuthorizationOptions

        public init(
            symbol: String = "bell.badge", title: String = "Notifications", why: String,
            required: Bool = false, options: UNAuthorizationOptions = [.alert, .sound]
        ) {
            self.symbol = symbol
            self.title = title
            self.why = why
            self.required = required
            self.options = options
        }

        public var standing: Standing { Notifications.standing(Notifications.reach()) }
        public func act() { Notifications.request(options: options) }
    }
#endif
