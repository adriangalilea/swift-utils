import Foundation
import Observation

extension PermissionGrant {
    /// The hook: `handler` runs on the main thread with the grant's new
    /// standing each time it changes (never for an unchanged one, never for
    /// the current one at registration). No app writes a polling loop.
    ///
    /// Every standing is observable, so this is Observation all the way
    /// down: a Privacy switch publishes through the hub, a kind macOS does
    /// not announce through `Readings`, an app's own grant through whatever
    /// observable state its closure reads.
    @MainActor @discardableResult
    public func observe(_ handler: @escaping @MainActor (Standing) -> Void) -> Observer {
        let observer = Observer(grant: self, handler: handler)
        observer.track()
        return observer
    }

    /// A registration of `observe`. It lives until `cancel()`, whether or not
    /// it is kept: a hook an app forgot to keep is still a hook.
    @MainActor public final class Observer {
        private let grant: PermissionGrant
        private let handler: @MainActor (Standing) -> Void
        private var last: Standing
        private var cancelled = false

        init(grant: PermissionGrant, handler: @escaping @MainActor (Standing) -> Void) {
            self.grant = grant
            self.handler = handler
            self.last = grant.standing
        }

        public func cancel() { cancelled = true }

        func track() {
            withObservationTracking {
                _ = grant.standing
            } onChange: { [weak self] in
                Task { @MainActor in self?.changed() }
            }
        }

        private func changed() {
            guard !cancelled else { return }
            let now = grant.standing
            if now != last {
                last = now
                handler(now)
            }
            track()
        }
    }

    /// A surface showing grants appeared (a row, a section, a chip, the
    /// menu that holds one): the person may be about to act on what it says,
    /// so the facts are read fresh now, and on a Mac every 2 s for the next
    /// two minutes (the hub's settings window). Never a standing loop.
    static func surfaceAppeared() {
        #if os(macOS)
            PrivacyHub.shared.watchSettings("a surface appeared")
        #else
            Readings.shared.readAll()
        #endif
    }
}

/// The standings of the kinds macOS does not announce (a background
/// service's registration, a notification setting, Apple Events consent),
/// made observable like the Privacy hub's: the first read of each is
/// synchronous and fresh, then it is read again only when something may have
/// changed it (an ask, a surface appearing, the app coming forward, and on a
/// Mac inside the hub's settings window), and a change publishes to every
/// view and hook that read it.
final class Readings: @unchecked Sendable, Observable {
    static let shared = Readings()

    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private var cached: [String: PermissionGrant.Standing] = [:]
    private var readers: [String: @Sendable () -> PermissionGrant.Standing] = [:]
    /// Bumped on every change: what Observation tracks.
    private var revision = 0

    private init() {
        for name in Platform.rereadOn {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) {
                [weak self] _ in self?.readAll()
            }
        }
    }

    /// The current standing under `key`, read with `read` the first time.
    func standing(
        _ key: String, _ read: @escaping @Sendable () -> PermissionGrant.Standing
    ) -> PermissionGrant.Standing {
        registrar.access(self, keyPath: \.revision)
        if let known = lock.withLock({ cached[key] }) { return known }
        let fresh = read()
        lock.withLock {
            cached[key] = fresh
            readers[key] = read
        }
        #if os(macOS)
            // The hub's window drives these reads too: start it even in an
            // app with no Privacy grant (chill: a daemon only).
            PrivacyHub.shared.start()
        #endif
        return fresh
    }

    /// Every standing read so far, read again; one publish if any moved.
    func readAll() {
        let all = lock.withLock { readers }
        var moved = false
        for (key, read) in all {
            let fresh = read()
            lock.withLock {
                if cached[key] != fresh {
                    cached[key] = fresh
                    moved = true
                }
            }
        }
        guard moved else { return }
        registrar.withMutation(of: self, keyPath: \.revision) {
            lock.withLock { revision += 1 }
        }
    }
}
