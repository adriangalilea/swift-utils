#if os(macOS) || os(iOS) || os(watchOS)
    import UserNotifications
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif

    extension PermissionGrant {
        /// Notifications, the one permission the notification daemon owns
        /// per bundle rather than tccd.
        ///
        /// The reach is a FACT the person changes in Settings at any moment,
        /// never a value an app keeps: every surface reads it fresh. An app
        /// that asked once at launch and remembered the answer shows "off"
        /// after the person turned it on.
        ///
        /// macOS: UNUserNotificationCenter only serves a BUNDLED app launched
        /// in the user's context (LaunchServices). A bare binary or a launchd
        /// agent cannot ask, read, or post; such a process hands its messages
        /// to a nested helper app, learns the reach from what the helper
        /// records, and declares a custom grant whose standing is
        /// `standing(recorded)` and whose act opens the HELPER's settings.
        public enum Notifications {
            /// Whether the person SEES this app's notifications. "Authorized"
            /// alone lies: an app allowed with every on-screen delivery off,
            /// or delivered quietly (provisional), posts into a list and
            /// interrupts nobody, which for a message that matters is denied.
            public enum Reach: String, Codable, Sendable {
                /// The system prompt has never been shown. One ask is available.
                case notAsked
                /// The person said no. Only Settings can flip it.
                case denied
                /// Allowed, but nothing appears where the person looks: alerts
                /// off (macOS: alert style None; iOS: banners and Lock Screen
                /// both off), or quiet (provisional) delivery.
                case silenced
                /// Banners or alerts reach the screen.
                case allowed
            }

            /// Synchronous, for the surfaces' pulse: one XPC round trip.
            /// nil = no answer within `timeout`, or a status this build does
            /// not know, which `standing` renders as unknown.
            public static func reach(timeout: TimeInterval = 2) -> Reach? {
                final class Answer: @unchecked Sendable { var reach: Reach? }
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
            public static func reach() async -> Reach? {
                reach(of: await UNUserNotificationCenter.current().notificationSettings())
            }

            public static func reach(of settings: UNNotificationSettings) -> Reach? {
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
            /// Lock Screen while it is not.
            private static func seen(_ settings: UNNotificationSettings) -> Bool {
                #if os(macOS)
                    settings.alertSetting == .enabled && settings.alertStyle != .none
                #elseif os(watchOS)
                    settings.alertSetting == .enabled
                #else
                    settings.alertSetting == .enabled || settings.lockScreenSetting == .enabled
                #endif
            }

            /// First ask fires the system prompt; after any answer the system
            /// never prompts again, so asking again opens this app's own
            /// notification settings.
            public static func ask(
                options: UNAuthorizationOptions = [.alert, .sound],
                bundleID: String = Bundle.main.bundleIdentifier!
            ) async {
                guard await reach() == .notAsked else { return openSettings(bundleID: bundleID) }
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                    options: options)
            }

            /// The app's notification settings. macOS: System Settings ›
            /// Notifications scrolled to `bundleID`'s row (a helper that posts
            /// on another process's behalf passes the HELPER's id: the row
            /// belongs to whoever posts). iOS: Settings › this app ›
            /// Notifications (only the calling app's own; `bundleID` unused).
            public static func openSettings(bundleID: String) {
                #if os(macOS)
                    NSWorkspace.shared.open(
                        URL(
                            string:
                                "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)"
                        )!)
                #elseif os(iOS)
                    Task { @MainActor in
                        UIApplication.shared.open(
                            URL(string: UIApplication.openNotificationSettingsURLString)!)
                    }
                #endif
                // a watch opens no settings page for an app: its standing's note says where
            }

            #if os(macOS)
                static let settingsName = "System Settings"
                static let system = "macOS"
                static let fixTitle = "Open System Settings\u{2026}"
                static let silencedNote =
                    "Allowed, but alerts are off: messages land in Notification Center without appearing."
            #elseif os(watchOS)
                static let settingsName = "the Watch app on the iPhone › Notifications"
                static let system = "watchOS"
                /// a watch opens no settings page: the button points at the note, which is the fix
                static let fixTitle = "How\u{2026}"
                static let silencedNote =
                    "Allowed, but alerts are off: the Watch app on the iPhone › Notifications › this app."
            #else
                static let settingsName = "Settings"
                static let system = "iOS"
                static let fixTitle = "Open Settings\u{2026}"
                static let silencedNote =
                    "Allowed, but banners and the Lock Screen are both off: messages land in Notification Centre without appearing."
            #endif

            /// The one derivation from reach to standing, shared by every app
            /// so no two of them disagree on what a silenced app means.
            public static func standing(_ reach: Reach?) -> Standing {
                switch reach {
                case .allowed: .good
                case .notAsked: .askable("Allow\u{2026}")
                case .denied:
                    .broken(
                        fixTitle,
                        note:
                            "Notifications are off in \(settingsName). \(system) never asks twice."
                    )
                case .silenced:
                    .broken(fixTitle, note: silencedNote)
                case nil:
                    .unknown(note: "Notification settings did not answer.")
                }
            }
        }
    }
#endif
