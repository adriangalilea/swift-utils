import AppKit
import Keymap
import SwiftUI

// The system-wide shortcut overlay: an accessory-policy agent (no Dock
// icon, no menu bar) holding ONE Carbon chord - ⌃⌘/ ("what can I press
// here?"). On fire it shows a nonactivating floating panel with the
// FRONTMOST app's published keymap (the manifest every Keymap-adopting app
// writes to ~/Library/Application Support/untitled/keymaps), tinted with
// that app's accent. Chord again, Esc-shaped clicks, or any click outside
// dismisses. No IPC: the manifests on disk ARE the protocol.

@MainActor
final class Overlay {
    private let float = FloatingPanel()
    private var hotkey: GlobalHotkey?

    func start() {
        // ⌃⌘/ - kVK_ANSI_Slash is 44; modifiers via the same Carbon masks
        // the library uses.
        hotkey = GlobalHotkey(
            keyCode: 44, modifiers: KeyCombo("/", [.command, .control]).carbonModifiers
        ) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
        // The built-in contract: any click anywhere, or an app switch (the
        // frontmost changing under the card would make it lie), dismisses.
        float.onDismissRequest = { [weak self] in self?.float.dismiss() }
    }

    private func toggle() {
        if float.isVisible {
            float.dismiss()
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        let manifest = front?.bundleIdentifier.flatMap(Self.manifest(for:))
        float.show(
            OverlayView(manifest: manifest, appName: front?.localizedName ?? "this app"),
            on: NSScreen.main
        )
    }

    private static func manifest(for bundleID: String) -> KeymapManifest? {
        guard let data = try? Data(contentsOf: KeymapManifest.url(forBundleID: bundleID)) else {
            return nil
        }
        return try? JSONDecoder().decode(KeymapManifest.self, from: data)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let overlay = Overlay()
overlay.start()
app.run()
