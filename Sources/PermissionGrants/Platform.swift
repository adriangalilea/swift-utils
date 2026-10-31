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

    /// What the system announces that may move a standing `Readings` holds:
    /// the app coming forward everywhere, and on the iPhone the background
    /// refresh switch, which UIKit announces on its own.
    #if os(iOS)
        static let rereadOn = [
            becameActive, UIApplication.backgroundRefreshStatusDidChangeNotification,
        ]
    #else
        static let rereadOn = [becameActive]
    #endif

    /// The settings app's name, as the person knows it.
    #if os(macOS)
        static let settingsName = "System Settings"
    #else
        static let settingsName = "Settings"
    #endif

    /// The app as Settings lists it: its display name, else its bundle name.
    static let appName =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "this app"

    /// The device, as a note names it ("Restricted on this iPhone").
    #if os(watchOS)
        static let deviceName = "Apple Watch"
    #elseif os(iOS)
        static let deviceName = "iPhone"
    #else
        static let deviceName = "Mac"
    #endif

    /// Whether the app's Info.plist carries `key`: iOS and watchOS ignore an
    /// ask whose usage description is missing, without a word.
    static func declares(_ key: String) -> Bool {
        Bundle.main.object(forInfoDictionaryKey: key) is String
    }

    #if os(iOS)
        /// Settings › this app: the one page iOS lets an app open.
        @MainActor static func openAppSettings() {
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        }
    #endif
}
