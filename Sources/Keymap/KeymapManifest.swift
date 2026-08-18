import AppKit
import Foundation

/// The published face of an app's keymap: effective bindings (defaults +
/// remaps) as plain JSON on disk, rewritten on launch and on every change.
/// This is how the system-wide overlay knows what to display for the
/// frontmost app - no IPC, no protocol, just a file per bundle id in a
/// shared directory. Localized at write time (titles resolve through the
/// app's catalog), so the overlay renders without knowing any app.
public struct KeymapManifest: Codable, Sendable {
    /// Self-description for whoever opens the file cold: the schema URL is
    /// versioned (v1) and doubles as the context pointer to this repo.
    public static let schemaURL =
        "https://raw.githubusercontent.com/adriangalilea/swift-utils/main/Schemas/keymap.v1.json"

    public struct Action: Codable, Sendable {
        public let title: String
        public let symbol: String
        /// Display strings ("⇧⌘K"), already ordered: in-app combos first.
        public let local: [String]
        public let global: [String]
    }

    public struct Section: Codable, Sendable {
        public let name: String
        public let actions: [Action]
    }

    public let schema: String
    public let bundleID: String
    public let appName: String
    /// The app's accent, "#RRGGBB" - the overlay tints per app.
    public let accent: String
    public let sections: [Section]

    enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case bundleID, appName, accent, sections
    }

    /// The shared directory both sides agree on.
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("untitled/keymaps", isDirectory: true)
    }

    public static func url(forBundleID bundleID: String) -> URL {
        directory.appendingPathComponent("\(bundleID).json")
    }
}

extension KeymapStore {
    /// Wire the store to the shared keymap directory: writes the manifest
    /// now and again after every change. Call once at launch.
    public func publish(appName: String, accent: String) {
        let write = { [weak self] in
            guard let self else { return }
            let bundleID = Bundle.main.bundleIdentifier ?? appName
            let manifest = KeymapManifest(
                schema: KeymapManifest.schemaURL,
                bundleID: bundleID,
                appName: appName,
                accent: accent,
                sections: A.sections.map { section in
                    KeymapManifest.Section(
                        name: section.name,
                        actions: section.actions.map { action in
                            KeymapManifest.Action(
                                title: action.spec.title,
                                symbol: action.spec.symbol,
                                local: self.combos(for: action, .local).map(\.display),
                                global: self.combos(for: action, .global).map(\.display)
                            )
                        }
                    )
                }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                try FileManager.default.createDirectory(
                    at: KeymapManifest.directory, withIntermediateDirectories: true)
                try encoder.encode(manifest).write(
                    to: KeymapManifest.url(forBundleID: bundleID), options: .atomic)
            } catch {
                // Publishing is a courtesy to the overlay, never worth
                // failing the app for - but say so once per session.
                NSLog("Keymap: manifest publish failed: \(error)")
            }
        }
        write()
        onChange(write)
    }
}
