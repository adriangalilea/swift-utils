#if os(iOS)
    import Foundation
    import Log
    import UIKit

    extension PermissionGrant {
        /// Background App Refresh: whether iOS wakes the app while it is
        /// closed (a location event, a fetch, a task). iOS has no prompt for
        /// it, so its fix is always the app's Settings page; UIKit announces
        /// each change, and `Readings` re-reads it then.
        enum BackgroundRefresh {
            static func standing() -> Standing {
                switch status() {
                case .available: .good
                case .denied:
                    .broken(
                        "Open Settings\u{2026}",
                        note:
                            "Off in Settings › Apps › \(Platform.appName) › Background App Refresh, or for every app in Settings › General › Background App Refresh."
                    )
                case .restricted:
                    .unknown(
                        note:
                            "Restricted on this \(Platform.deviceName): the person cannot turn it on."
                    )
                @unknown default: .unknown(note: "iOS gave a status this build does not know.")
                }
            }

            @MainActor static func ask() {
                log.scope("grant").info(
                    "asked", ["grant": "background refresh", "answered": "\(status().rawValue)"])
                Platform.openAppSettings()
            }

            /// UIKit answers on the main thread; a reading from elsewhere waits for it there.
            private static func status() -> UIBackgroundRefreshStatus {
                if Thread.isMainThread {
                    return MainActor.assumeIsolated { UIApplication.shared.backgroundRefreshStatus }
                }
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated { UIApplication.shared.backgroundRefreshStatus }
                }
            }
        }
    }
#endif
