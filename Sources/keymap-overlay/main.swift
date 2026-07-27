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
    private var panel: NSPanel?
    private var hotkey: GlobalHotkey?
    private var clickMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?

    func start() {
        // ⌃⌘/ - kVK_ANSI_Slash is 44; modifiers via the same Carbon masks
        // the library uses.
        hotkey = GlobalHotkey(keyCode: 44, modifiers: KeyCombo("/", [.command, .control]).carbonModifiers) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
    }

    private func toggle() {
        if panel != nil { dismiss() } else { show() }
    }

    private func show() {
        let front = NSWorkspace.shared.frontmostApplication
        let manifest = front?.bundleIdentifier.flatMap(Self.manifest(for:))
        let view = OverlayView(
            manifest: manifest,
            appName: front?.localizedName ?? "this app"
        )
        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - hosting.fittingSize.width / 2,
                y: frame.midY - hosting.fittingSize.height / 2
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        // Any click anywhere dismisses (global = other apps, local = ours).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        // The frontmost app changing under the panel would make it lie.
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil
    }

    private static func manifest(for bundleID: String) -> KeymapManifest? {
        guard let data = try? Data(contentsOf: KeymapManifest.url(forBundleID: bundleID)) else { return nil }
        return try? JSONDecoder().decode(KeymapManifest.self, from: data)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let overlay = Overlay()
overlay.start()
app.run()
