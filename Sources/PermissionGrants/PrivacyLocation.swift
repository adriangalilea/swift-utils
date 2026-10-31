#if os(iOS) || os(watchOS)
    import CoreLocation
    import Foundation
    import Log
    import os

    private let grantLog = log.scope("grant")

    extension PermissionGrant {
        /// Location's three grants (`.location`, `.locationAlways`,
        /// `.preciseLocation`) over the library's ONE `CLLocationManager`:
        /// its delegate hears every change of authorization and accuracy and
        /// publishes it through `Readings`, so a row and an `observe` hook move
        /// the moment the person answers or comes back from Settings, without
        /// polling. Location Services' system switch can block its caller, so it
        /// is read off the main thread and held, on until read.
        final class LocationAuthority: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
            static let shared = LocationAuthority()

            private struct State {
                var servicesOn = true
                /// Asks waiting for the person's answer, resumed by the next change.
                var waiting: [CheckedContinuation<Void, Never>] = []
            }

            private let manager: CLLocationManager
            private let state = OSAllocatedUnfairLock(initialState: State())

            /// iOS answers the upgrade to Always once and never says whether it
            /// was spent, so the app remembers its own ask: the one memory here.
            private static let alwaysAskedKey = "PermissionGrant.locationAlwaysAsked"

            /// Core Location calls a delegate on the run loop of the thread that
            /// made its manager, so the manager is made on the main thread.
            private override init() {
                manager =
                    Thread.isMainThread
                    ? CLLocationManager() : DispatchQueue.main.sync { CLLocationManager() }
                super.init()
                manager.delegate = self
                readServices()
            }

            func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
                let woken = state.withLock { s in
                    defer { s.waiting = [] }
                    return s.waiting
                }
                Readings.shared.readAll()
                for ask in woken { ask.resume() }
                readServices()
            }

            private func readServices() {
                Task.detached(priority: .utility) { [self] in
                    let on = CLLocationManager.locationServicesEnabled()
                    let moved = state.withLock { s in
                        defer { s.servicesOn = on }
                        return s.servicesOn != on
                    }
                    if moved { Readings.shared.readAll() }
                }
            }

            private var servicesOn: Bool { state.withLock { $0.servicesOn } }
            private var alwaysAsked: Bool {
                UserDefaults.standard.bool(forKey: Self.alwaysAskedKey)
            }

            private static func allowed(_ status: CLAuthorizationStatus) -> Bool {
                status == .authorizedWhenInUse || status == .authorizedAlways
            }

            private static func name(_ status: CLAuthorizationStatus) -> String {
                switch status {
                case .notDetermined: "not asked"
                case .restricted: "restricted"
                case .denied: "denied"
                case .authorizedAlways: "always"
                case .authorizedWhenInUse: "while using"
                @unknown default: "status \(status.rawValue)"
                }
            }

            /// An entry of `NSLocationTemporaryUsageDescriptionDictionary`, the
            /// reason the temporary precise prompt shows for `purposeKey`.
            private static func declaresPurpose(_ purposeKey: String) -> Bool {
                let reasons =
                    Bundle.main.object(forInfoDictionaryKey: temporaryUsageKey) as? [String: String]
                return reasons?[purposeKey] != nil
            }

            private static let temporaryUsageKey = "NSLocationTemporaryUsageDescriptionDictionary"

            private static var servicesOff: Standing {
                #if os(watchOS)
                    DevicePrivacy.broken(
                        "Location Services are off: Settings › Privacy & Security › Location Services on the watch."
                    )
                #else
                    DevicePrivacy.broken(
                        "Location Services are off: Settings › Privacy & Security › Location Services."
                    )
                #endif
            }

            func standing(_ p: Privacy, purposeKey: String?) -> Standing {
                let status = manager.authorizationStatus
                if !Self.allowed(status) && !servicesOn { return Self.servicesOff }
                if p == .preciseLocation { return precise(status, purposeKey) }
                switch status {
                case .authorizedAlways: return .good
                case .authorizedWhenInUse:
                    guard p == .locationAlways else { return .good }
                    if alwaysAsked {
                        return DevicePrivacy.broken("Set to Always in \(p.whereToFix).")
                    }
                    guard Platform.declares(p.usageKey!) else {
                        return DevicePrivacy.undeclared(p.usageKey!)
                    }
                    return .askable("Allow Always\u{2026}")
                case .notDetermined:
                    guard Platform.declares(Privacy.location.usageKey!) else {
                        return DevicePrivacy.undeclared(Privacy.location.usageKey!)
                    }
                    return .askable("Allow\u{2026}")
                case .restricted:
                    return DevicePrivacy.broken("Restricted on this \(Platform.deviceName).")
                case .denied: return DevicePrivacy.broken("Off in \(Privacy.location.whereToFix).")
                @unknown default:
                    return DevicePrivacy.broken("Off in \(Privacy.location.whereToFix).")
                }
            }

            /// Precise follows Location: nothing to say until Location is allowed.
            /// Temporary full accuracy reads as precise while it lasts, since
            /// that is what the app gets; the delegate reports its end.
            private func precise(_ status: CLAuthorizationStatus, _ purposeKey: String?) -> Standing
            {
                guard Self.allowed(status) else { return .unknown(note: "Follows Location.") }
                let off = "Precise Location is off: \(Privacy.preciseLocation.whereToFix)."
                switch manager.accuracyAuthorization {
                case .fullAccuracy: return .good
                case .reducedAccuracy:
                    guard let purposeKey else { return DevicePrivacy.broken(off) }
                    guard Self.declaresPurpose(purposeKey) else {
                        return DevicePrivacy.undeclared("\(Self.temporaryUsageKey) › \(purposeKey)")
                    }
                    return .broken("Allow Precise\u{2026}", note: off)
                @unknown default: return DevicePrivacy.broken(off)
                }
            }

            /// Never asked: While Using, the prompt (Always and Precise start
            /// there too). While Using, for Always: the one upgrade. Reduced,
            /// for Precise: the temporary prompt for the grant's purpose, else
            /// Settings. Anything else: Settings, where only the person can change it.
            @MainActor func ask(_ p: Privacy, purposeKey: String?) async {
                let status = manager.authorizationStatus
                guard Self.allowed(status) || servicesOn else {
                    return DevicePrivacy.reopenSettings(p, "Location Services off")
                }
                switch (p, status) {
                case (_, .notDetermined):
                    guard DevicePrivacy.declared(Privacy.location.usageKey!, for: p) else { return }
                    await answer { $0.requestWhenInUseAuthorization() }
                    DevicePrivacy.asked(p, Self.name(manager.authorizationStatus))
                case (.locationAlways, .authorizedWhenInUse):
                    guard !alwaysAsked else {
                        return DevicePrivacy.reopenSettings(p, "upgrade asked before")
                    }
                    guard DevicePrivacy.declared(p.usageKey!, for: p) else { return }
                    await upgradeToAlways()
                case (.preciseLocation, .authorizedWhenInUse),
                    (.preciseLocation, .authorizedAlways):
                    guard manager.accuracyAuthorization == .reducedAccuracy else { return }
                    guard let purposeKey else {
                        return DevicePrivacy.reopenSettings(p, "reduced accuracy")
                    }
                    guard Self.declaresPurpose(purposeKey) else {
                        grantLog.error(
                            "the ask needs a usage description",
                            ["grant": p.title, "key": "\(Self.temporaryUsageKey) › \(purposeKey)"])
                        return
                    }
                    do {
                        try await manager.requestTemporaryFullAccuracyAuthorization(
                            withPurposeKey: purposeKey)
                    } catch {
                        grantLog.error("the ask failed", ["grant": p.title, "err": error])
                    }
                    let precise = manager.accuracyAuthorization == .fullAccuracy
                    DevicePrivacy.asked(p, precise ? "precise" : "approximate")
                case (_, .authorizedAlways), (.location, .authorizedWhenInUse): return
                default: DevicePrivacy.reopenSettings(p, Self.name(status))
                }
            }

            /// Makes the request, then waits for the delegate to report the answer.
            @MainActor private func answer(_ request: (CLLocationManager) -> Void) async {
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    state.withLock { $0.waiting.append(done) }
                    request(manager)
                }
            }

            /// The upgrade from While Using to Always: a `CLServiceSession` that
            /// requires Always, held in the foreground, makes iOS show its one
            /// upgrade prompt; its diagnostics say when the request is under way
            /// and when it ended. A session whose request never begins within
            /// ten seconds is given up (iOS asked nothing) and logged.
            @MainActor private func upgradeToAlways() async {
                UserDefaults.standard.set(true, forKey: Self.alwaysAskedKey)
                let session = CLServiceSession(authorization: .always)
                let began = OSAllocatedUnfairLock(initialState: false)
                // true: the request ended; false: the ten seconds passed.
                let (events, sink) = AsyncStream.makeStream(of: Bool.self)
                let follow = Task {
                    do {
                        for try await d in session.diagnostics {
                            if d.authorizationRequestInProgress {
                                began.withLock { $0 = true }
                                continue
                            }
                            if began.withLock({ $0 }) || d.alwaysAuthorizationDenied
                                || d.authorizationDenied || d.authorizationDeniedGlobally
                                || d.authorizationRestricted
                            {
                                break
                            }
                        }
                    } catch {
                        grantLog.error("the Always session failed", ["err": error])
                    }
                    sink.yield(true)
                }
                let timer = Task {
                    try? await Task.sleep(for: .seconds(10))
                    sink.yield(false)
                }
                for await ended in events where ended || !began.withLock({ $0 }) { break }
                follow.cancel()
                timer.cancel()
                session.invalidate()
                let status = manager.authorizationStatus
                if !began.withLock({ $0 }) && status != .authorizedAlways {
                    grantLog.error(
                        "the Always session asked nothing", ["grant": Privacy.locationAlways.title])
                }
                DevicePrivacy.asked(.locationAlways, Self.name(status))
            }
        }
    }
#endif
