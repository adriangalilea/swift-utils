#if os(iOS) || os(watchOS)
    import CoreMotion
    import EventKit
    import Foundation
    import Log
    #if os(iOS)
        import AlarmKit
    #endif

    private let grantLog = log.scope("grant")

    extension PermissionGrant {
        /// The Privacy switches a grant reads on an iPhone and an Apple Watch,
        /// by the same names as on a Mac where both have one (`.privacy(.calendars, …)`
        /// and `.privacy(.motion, …)` compile on all three). Unlike macOS,
        /// these platforms answer a running app live, so the public status is
        /// the truth: location publishes each change through the library's
        /// one `CLLocationManager`, the rest are read when a surface appears,
        /// after an ask, and when the app comes forward.
        public enum Privacy: String, Sendable, CaseIterable {
            /// Read and change events (EventKit's full access; "add only" counts as off).
            case calendars
            /// Read and change reminders (EventKit's full access).
            case reminders
            #if os(iOS)
                /// Schedule alarms and timers that ring through Silent and Focus (AlarmKit).
                case alarms
            #endif
            /// Location While Using the App, or Always: the app's own position
            /// while it is in use. Needs `NSLocationWhenInUseUsageDescription`.
            case location
            /// Location Always, asked in two steps: While Using first, then the
            /// one upgrade iOS allows, through a foreground `CLServiceSession`.
            /// Needs `NSLocationAlwaysAndWhenInUseUsageDescription` as well.
            case locationAlways
            /// Precise Location, which follows Location: unknown until Location
            /// is allowed. Declared with a `purposeKey`, its ask is the temporary
            /// full accuracy prompt for that purpose (an entry of
            /// `NSLocationTemporaryUsageDescriptionDictionary`); without one, Settings.
            case preciseLocation
            /// Motion & Fitness, read through `CMMotionActivityManager` (the switch
            /// macOS's `.motion` reads too). Needs `NSMotionUsageDescription`.
            case motion

            var title: String {
                switch self {
                case .calendars: "Calendars"
                case .reminders: "Reminders"
                #if os(iOS)
                    case .alarms: "Alarms"
                #endif
                case .location: "Location"
                case .locationAlways: "Location Always"
                case .preciseLocation: "Precise Location"
                case .motion: "Motion & Fitness"
                }
            }

            var symbol: String {
                switch self {
                case .calendars: "calendar"
                case .reminders: "checklist"
                #if os(iOS)
                    case .alarms: "alarm"
                #endif
                case .location: "location"
                case .locationAlways: "location.circle"
                case .preciseLocation: "scope"
                case .motion: "figure.walk"
                }
            }

            /// The Info.plist key without which the system ignores the ask.
            var usageKey: String? {
                switch self {
                case .location: "NSLocationWhenInUseUsageDescription"
                case .locationAlways: "NSLocationAlwaysAndWhenInUseUsageDescription"
                case .motion: "NSMotionUsageDescription"
                default: nil
                }
            }

            /// Where the person turns it back on, said in the note of a broken standing.
            var whereToFix: String {
                #if os(watchOS)
                    switch self {
                    case .location, .locationAlways, .preciseLocation:
                        "Settings › Privacy & Security › Location Services › \(Platform.appName) on the watch"
                    default:
                        // A watch app's privacy follows its iPhone app's where one exists.
                        "Settings › Privacy & Security › \(title) on the iPhone or the watch"
                    }
                #else
                    switch self {
                    case .alarms: "Settings › Apps › \(Platform.appName) › Alarms"
                    case .location:
                        "Settings › Privacy & Security › Location Services › \(Platform.appName)"
                    case .locationAlways, .preciseLocation:
                        "Settings › Apps › \(Platform.appName) › Location"
                    default: "Settings › Privacy & Security › \(title)"
                    }
                #endif
            }
        }

        enum DevicePrivacy {
            static func standing(_ p: Privacy, purposeKey: String?) -> Standing {
                switch p {
                case .location, .locationAlways, .preciseLocation:
                    LocationAuthority.shared.standing(p, purposeKey: purposeKey)
                case .motion: Motion.standing()
                default: Store.standing(p)
                }
            }

            @MainActor static func ask(_ p: Privacy, purposeKey: String?) async {
                switch p {
                case .location, .locationAlways, .preciseLocation:
                    await LocationAuthority.shared.ask(p, purposeKey: purposeKey)
                case .motion: await Motion.ask()
                default: await Store.ask(p)
                }
            }

            /// iOS opens the app's own Settings page; a watch can open none, so its note is the fix.
            static func broken(_ note: String) -> Standing {
                #if os(iOS)
                    .broken("Open Settings\u{2026}", note: note)
                #else
                    .broken("How\u{2026}", note: note)
                #endif
            }

            /// A usage description the app's Info.plist lacks: the system would
            /// ignore the ask without a word, so the standing says it instead.
            static func undeclared(_ key: String) -> Standing {
                .broken(
                    "How\u{2026}",
                    note: "The app's Info.plist has no \(key), so the system ignores the ask.")
            }

            /// Logged as an error when an ask meets an undeclared key, and the ask stops there.
            static func declared(_ key: String, for p: Privacy) -> Bool {
                guard Platform.declares(key) else {
                    grantLog.error(
                        "the ask needs a usage description", ["grant": p.title, "key": key])
                    return false
                }
                return true
            }

            /// Not asked: the system prompt. Otherwise iOS opens Settings; the watch's note already says where.
            @MainActor static func reopenSettings(_ p: Privacy, _ before: String) {
                grantLog.info("asked again", ["grant": p.title, "before": before])
                #if os(iOS)
                    Platform.openAppSettings()
                #endif
            }

            static func asked(_ p: Privacy, _ answer: String) {
                grantLog.info("asked", ["grant": p.title, "answered": answer])
            }
        }

        /// EventKit's calendars and reminders, and AlarmKit's alarms.
        enum Store {
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
                default: preconditionFailure("\(p.title) is not EventKit's or AlarmKit's")
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
                switch answer(p) {
                case .allowed: .good
                case .notAsked: .askable("Allow\u{2026}")
                case .addOnly:
                    DevicePrivacy.broken("Only adding is allowed: \(p.whereToFix) › Full Access.")
                case .denied: DevicePrivacy.broken("Off in \(p.whereToFix).")
                }
            }

            @MainActor static func ask(_ p: Privacy) async {
                let before = answer(p)
                guard before == .notAsked else {
                    return DevicePrivacy.reopenSettings(p, before.rawValue)
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
                    default: preconditionFailure("\(p.title) is not EventKit's or AlarmKit's")
                    }
                } catch {
                    grantLog.error("the ask failed", ["grant": p.title, "err": error])
                    return
                }
                DevicePrivacy.asked(p, granted ? "allowed" : "denied")
            }
        }

        /// Motion & Fitness. iOS announces no change to it: it is re-read when
        /// the app comes forward, as the stores are.
        enum Motion {
            static func standing() -> Standing {
                guard CMMotionActivityManager.isActivityAvailable() else {
                    return .unknown(note: "This device records no motion.")
                }
                switch CMMotionActivityManager.authorizationStatus() {
                case .authorized: return .good
                case .notDetermined:
                    guard Platform.declares(Privacy.motion.usageKey!) else {
                        return DevicePrivacy.undeclared(Privacy.motion.usageKey!)
                    }
                    return .askable("Allow\u{2026}")
                case .restricted:
                    return DevicePrivacy.broken("Restricted on this \(Platform.deviceName).")
                case .denied: return DevicePrivacy.broken("Off in \(Privacy.motion.whereToFix).")
                @unknown default:
                    return DevicePrivacy.broken("Off in \(Privacy.motion.whereToFix).")
                }
            }

            /// A one-minute activity query is what makes the system prompt;
            /// its handler runs once the person answered.
            @MainActor static func ask() async {
                let before = CMMotionActivityManager.authorizationStatus()
                guard before == .notDetermined else {
                    return DevicePrivacy.reopenSettings(.motion, "\(before.rawValue)")
                }
                guard DevicePrivacy.declared(Privacy.motion.usageKey!, for: .motion) else { return }
                let manager = CMMotionActivityManager()
                let now = Date()
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    manager.queryActivityStarting(
                        from: now.addingTimeInterval(-60), to: now, to: .main
                    ) { _, _ in done.resume() }
                }
                withExtendedLifetime(manager) {}
                let after = CMMotionActivityManager.authorizationStatus()
                DevicePrivacy.asked(.motion, after == .authorized ? "allowed" : "denied")
            }
        }
    }
#endif
