import Foundation

#if os(macOS)
    import AppKit
#elseif os(watchOS)
    import WatchKit
#else
    import UIKit
#endif

/// What differs per platform, said once: when the app comes forward (a
/// standing may have changed while it was away), and where the person
/// changes an app's permissions.
enum Platform {
    #if os(macOS)
        static let becameActive = NSApplication.didBecomeActiveNotification
    #elseif os(watchOS)
        static let becameActive = WKApplication.didBecomeActiveNotification
    #else
        static let becameActive = UIApplication.didBecomeActiveNotification
    #endif

    /// The settings app's name, as the person knows it.
    #if os(macOS)
        static let settingsName = "System Settings"
    #else
        static let settingsName = "Settings"
    #endif

    #if os(iOS)
        /// Settings › this app: the one page iOS lets an app open.
        @MainActor static func openAppSettings() {
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        }
    #endif
}
