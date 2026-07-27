import AppKit
import SwiftUI

/// THE floating-surface host - a nonactivating glass panel with the
/// dismissal contract BUILT IN, because every hand-rolled float forgot part
/// of it: clicking ANYWHERE outside the panel dismisses - inside this app
/// (local monitor), inside ANY OTHER app (global monitor, no permissions
/// needed for mouse events), or switching apps at all. Esc stays the
/// host's key monitor (hosts own dismissal keys); this owns the pointer
/// side. One instance per surface; `show` replaces, `dismiss` tears down.
@MainActor
public final class FloatingPanel {
    private var panel: NSPanel?
    private var localClicks: Any?
    private var globalClicks: Any?
    private var appSwitch: NSObjectProtocol?

    /// Fired on any built-in dismissal trigger. The HOST flips its own
    /// state (which calls `dismiss()`) - the panel never closes itself, so
    /// host state can't drift from what's on screen.
    public var onDismissRequest: (() -> Void)?

    public init() {}

    /// `dismissOnAppSwitch`: on for app-owned surfaces (a cheat panel over
    /// a deactivated app is stale chrome); off for agents whose whole job
    /// is showing over other apps' frontmost moments.
    public func show(
        _ content: some View,
        size: NSSize? = nil,
        on screen: NSScreen?,
        dismissOnAppSwitch: Bool = true
    ) {
        dismiss()
        let hosting = NSHostingView(rootView: content)
        let size = size ?? hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        if let frame = (screen ?? NSScreen.main)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        localClicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel { self.onDismissRequest?() }
            }
            return event
        }
        globalClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDismissRequest?() }
        }
        if dismissOnAppSwitch {
            appSwitch = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onDismissRequest?() }
            }
        }
    }

    public func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        if let localClicks { NSEvent.removeMonitor(localClicks) }
        localClicks = nil
        if let globalClicks { NSEvent.removeMonitor(globalClicks) }
        globalClicks = nil
        if let appSwitch { NSWorkspace.shared.notificationCenter.removeObserver(appSwitch) }
        appSwitch = nil
    }

    public var isVisible: Bool { panel != nil }
}
