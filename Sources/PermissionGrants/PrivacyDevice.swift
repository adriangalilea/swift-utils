#if os(iOS) || os(watchOS)
    import EventKit
    import Foundation
    import Log
    #if os(iOS)
        import AlarmKit
    #endif

    private let grantLog = log.scope("grant")

    extension PermissionGrant {
        /// The Privacy switches a grant reads on an iPhone and an Apple Watch,
        /// by the same names as on a Mac (`.privacy(.calendars, …)` compiles
        /// on all three). Unlike macOS, these platforms answer a running app
        /// live, so the public status is the truth: read when a surface
        /// appears, after an ask, and when the app comes forward.
        public enum Privacy: String, Sendable, CaseIterable {
            /// Read and change events (EventKit's full access; "add only" counts as off).
            case calendars
            /// Read and change reminders (EventKit's full access).
            case reminders
            #if os(iOS)
                /// Schedule alarms and timers that ring through Silent and Focus (AlarmKit).
                case alarms
            #endif

            var title: String {
                switch self {
                case .calendars: "Calendars"
                case .reminders: "Reminders"
                #if os(iOS)
                    case .alarms: "Alarms"
                #endif
                }
            }

            var symbol: String {
                switch self {
                case .calendars: "calendar"
                case .reminders: "checklist"
                #if os(iOS)
                    case .alarms: "alarm"
                #endif
                }
            }

            /// Where the person turns it back on, said in the note of a broken standing.
            var whereToFix: String {
                #if os(watchOS)
                    // A watch app's privacy follows its iPhone app's where one exists.
                    "Settings › Privacy & Security › \(title) on the iPhone or the watch"
                #else
                    switch self {
                    case .alarms: "Settings › Apps › this app › Alarms"
                    default: "Settings › Privacy & Security › \(title)"
                    }
                #endif
            }
        }

        enum DevicePrivacy {
            enum Answer: String {
                case allowed, denied, notAsked = "not asked", addOnly = "add only"
            }

            static func answer(_ p: Privacy) -> Answer {
                switch p {
                case .calendars: events(EKEventStore.authorizationStatus(for: .event))
                case .reminders: events(EKEventStore.authorizationStatus(for: .reminder))
                #if os(iOS)
                    case .alarms:
                        switch AlarmManager.shared.authorizationState {
                        case .authorized: .allowed
                        case .notDetermined: .notAsked
                        case .denied: .denied
                        @unknown default: .denied
                        }
                #endif
                }
            }

            static func events(_ s: EKAuthorizationStatus) -> Answer {
                switch s {
                case .fullAccess: .allowed
                case .notDetermined: .notAsked
                case .writeOnly: .addOnly
                case .denied, .restricted: .denied
                @unknown default: .denied
                }
            }

            static func standing(_ p: Privacy) -> Standing {
                let a = answer(p)
                return switch a {
                case .allowed: .good
                case .notAsked: .askable("Allow\u{2026}")
                case .addOnly:
                    brokenStanding("Only adding is allowed: \(p.whereToFix) › Full Access.")
                case .denied: brokenStanding("Off in \(p.whereToFix).")
                }
            }

            /// iOS opens the app's own Settings page; a watch can open none, so its note is the fix.
            private static func brokenStanding(_ note: String) -> Standing {
                #if os(iOS)
                    .broken("Open Settings\u{2026}", note: note)
                #else
                    .broken("How\u{2026}", note: note)
                #endif
            }

            /// Not asked: the system prompt. Otherwise iOS opens Settings; the watch's note already says where.
            @MainActor static func ask(_ p: Privacy) async {
                let before = answer(p)
                guard before == .notAsked else {
                    grantLog.info("asked again", ["grant": p.title, "before": before.rawValue])
                    #if os(iOS)
                        Platform.openAppSettings()
                    #endif
                    return
                }
                let granted: Bool
                do {
                    switch p {
                    case .calendars: granted = try await EKEventStore().requestFullAccessToEvents()
                    case .reminders:
                        granted = try await EKEventStore().requestFullAccessToReminders()
                    #if os(iOS)
                        case .alarms:
                            granted =
                                try await AlarmManager.shared.requestAuthorization() == .authorized
                    #endif
                    }
                } catch {
                    grantLog.error("the ask failed", ["grant": p.title, "err": error])
                    return
                }
                grantLog.info(
                    "asked", ["grant": p.title, "answered": granted ? "allowed" : "denied"])
            }
        }
    }
#endif
