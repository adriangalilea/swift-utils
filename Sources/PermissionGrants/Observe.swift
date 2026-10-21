import Foundation

#if os(macOS)
    import AppKit
    private let becameActive = NSApplication.didBecomeActiveNotification
#elseif os(iOS) || os(tvOS)
    import UIKit
    private let becameActive = UIApplication.didBecomeActiveNotification
#endif

extension PermissionGrant {
    /// The hook: `handler` runs on the main thread with the grant's new
    /// standing each time it changes (never for an unchanged one, never for
    /// the current one at registration). No app writes a polling loop.
    ///
    /// How a change is noticed, per kind: a Privacy switch through the hub
    /// (at once, from macOS's own signals and the fresh probe); everything
    /// macOS does not announce (a background service's approval, a
    /// notification setting, an app's own state) by one read every 2 s
    /// while any observer is registered, and at once when the app comes
    /// forward. Nothing is read once the last observer cancels.
    @MainActor @discardableResult
    public func observe(_ handler: @escaping @MainActor (Standing) -> Void) -> Observer {
        Watch.shared.add(self, handler)
    }

    /// A registration of `observe`. It lives until `cancel()`, whether or not
    /// it is kept: a hook an app forgot to keep is still a hook.
    @MainActor public final class Observer {
        fileprivate let id = UUID()
        public func cancel() { Watch.shared.remove(id) }
    }
}

/// Every registered hook, read at once on a signal and every 2 s otherwise.
@MainActor private final class Watch {
    static let shared = Watch()

    private struct Entry {
        let grant: PermissionGrant
        var last: PermissionGrant.Standing
        let handler: @MainActor (PermissionGrant.Standing) -> Void
    }
    private var entries: [UUID: Entry] = [:]
    private var timer: Timer?

    private init() {
        #if os(macOS)
            PrivacyHub.shared.observe { _, _ in
                MainActor.assumeIsolated { Watch.shared.check() }
            }
        #endif
        NotificationCenter.default.addObserver(
            forName: becameActive, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { Watch.shared.check() } }
    }

    func add(
        _ grant: PermissionGrant, _ handler: @escaping @MainActor (PermissionGrant.Standing) -> Void
    ) -> PermissionGrant.Observer {
        let observer = PermissionGrant.Observer()
        entries[observer.id] = Entry(grant: grant, last: grant.standing, handler: handler)
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated { Watch.shared.check() }
            }
        }
        return observer
    }

    func remove(_ id: UUID) {
        entries[id] = nil
        if entries.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private func check() {
        for (id, entry) in entries {
            let now = entry.grant.standing
            guard now != entry.last else { continue }
            entries[id]?.last = now
            entry.handler(now)
        }
    }
}
