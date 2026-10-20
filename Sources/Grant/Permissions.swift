#if os(macOS)
    import AppKit
    import Log
    import Observation

    private let grantLog = log.scope("grant")

    /// What macOS answers for one of this app's permissions, asked of tccd
    /// itself.
    public enum Answer: String, Sendable, Equatable {
        case allowed, denied
        /// No record: the person was never asked (or the record was reset).
        case notAsked = "not asked"
    }

    /// The live permissions of this app, ONE hub every surface and every
    /// check reads. Never a remembered answer:
    ///
    /// - The public probes remember their first answer for the life of the
    ///   process. `CGPreflightPostEventAccess` read "denied" in a running
    ///   utter 30 s after tccd recorded "allowed", and sent tccd nothing after
    ///   its first call (2026-10-20; `AXIsProcessTrusted` the same,
    ///   2026-10-18). Only a new process saw the change.
    /// - tccd is asked directly instead (`TCCAccessPreflight`, TCC.framework,
    ///   the SPI AudioCap and steno bind): measured one tccd query per call,
    ///   6-8 ms each, and a tri-state of its own (allowed / denied / no
    ///   record), so no "asked before" flag can contradict it.
    ///
    /// When it reads: the first time a permission is asked for, synchronously
    /// (a surface's first frame is the truth, never a loading state, never a
    /// guess); then, for every permission read since, off the main thread
    /// every 2 s, at once when the app becomes active, at once when macOS
    /// announces an Accessibility change, and right after every ask. A change
    /// publishes through Observation (a view that read it repaints) and to
    /// every `observe` handler, and is logged with tccd's raw answer.
    public final class Permissions: @unchecked Sendable {
        public static let shared = Permissions()

        /// The TCC services this hub reads, named for what they let an app do.
        public enum Service: String, Sendable, CaseIterable {
            /// The AX API: read and act on other apps' interfaces.
            case accessibility = "kTCCServiceAccessibility"
            /// Post keyboard and mouse events (typing into other apps);
            /// System Settings lists it under Accessibility.
            case postEvents = "kTCCServicePostEvent"
            /// Listen to the keyboard, write its LEDs ("Input Monitoring").
            case inputMonitoring = "kTCCServiceListenEvent"
            /// Record what the Mac plays (a Core Audio process tap,
            /// "System Audio Recording"); Apple ships no public probe.
            case systemAudio = "kTCCServiceAudioCapture"
            case microphone = "kTCCServiceMicrophone"

            var title: String {
                switch self {
                case .accessibility: "Accessibility"
                case .postEvents: "Posting events"
                case .inputMonitoring: "Input Monitoring"
                case .systemAudio: "System Audio Recording"
                case .microphone: "Microphone"
                }
            }
        }

        private let registrar = ObservationRegistrar()
        private let lock = NSLock()
        private var answers: [Service: Answer] = [:]
        private var handlers: [UUID: (Service, Answer) -> Void] = [:]
        private let queue = DispatchQueue(label: "grant.permissions", qos: .utility)
        private var started = false

        private init() {}

        /// The current answer. The first read of a service asks tccd now, on
        /// the calling thread, and starts watching it.
        public func answer(_ service: Service) -> Answer {
            registrar.access(self, keyPath: \.revision)
            if let known = lock.withLock({ answers[service] }) { return known }
            return refresh(service)
        }

        /// The hook: `handler` runs on the main thread with every change of
        /// any watched service (never for an unchanged reading). Keep the
        /// token; `cancel(_:)` it when done.
        @discardableResult
        public func observe(_ handler: @escaping (Service, Answer) -> Void) -> UUID {
            let token = UUID()
            lock.withLock { handlers[token] = handler }
            return token
        }

        public func cancel(_ token: UUID) {
            _ = lock.withLock { handlers.removeValue(forKey: token) }
        }

        /// Re-reads every watched service now, off the calling thread: the
        /// moment something may have changed (an ask, a return from
        /// System Settings).
        public func refreshSoon() {
            queue.async { [self] in
                for service in lock.withLock({ Array(answers.keys) }) { refresh(service) }
            }
        }

        /// Bumped on every change: what Observation tracks.
        private var revision = 0

        @discardableResult
        private func refresh(_ service: Service) -> Answer {
            let code = Self.preflight(service.rawValue)
            let answer: Answer =
                switch code {
                case 0: .allowed
                case 1: .denied
                default: .notAsked
                }
            let (changed, first) = lock.withLock { () -> (Bool, Bool) in
                let old = answers[service]
                answers[service] = answer
                return (old != answer, old == nil)
            }
            startIfNeeded()
            guard changed else { return answer }
            grantLog.info(
                first ? "reads \(answer.rawValue)" : "changed to \(answer.rawValue)",
                ["grant": service.title, "service": service.rawValue, "tccd": code])
            registrar.withMutation(of: self, keyPath: \.revision) {
                lock.withLock { revision += 1 }
            }
            if !first {
                let current = lock.withLock { Array(handlers.values) }
                DispatchQueue.main.async { for handler in current { handler(service, answer) } }
            }
            return answer
        }

        private func startIfNeeded() {
            let start = lock.withLock { () -> Bool in
                guard !started else { return false }
                started = true
                return true
            }
            guard start else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(500))
            timer.setEventHandler { [self] in
                for service in lock.withLock({ Array(answers.keys) }) { refresh(service) }
            }
            timer.resume()
            self.timer = timer
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.refreshSoon() }
            // Posted by macOS when the Accessibility list changes.
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: nil
            ) { [weak self] _ in self?.refreshSoon() }
        }

        private var timer: DispatchSourceTimer?

        private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
        typealias Request =
            @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

        /// A TCC.framework function, or a scream: an OS without it is a world
        /// this code no longer understands.
        static func tcc(_ name: String) -> UnsafeMutableRawPointer {
            let handle = dlopen(
                "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
            precondition(handle != nil, "TCC.framework failed to load")
            let symbol = dlsym(handle, name)
            precondition(symbol != nil, "\(name) missing from TCC.framework")
            return symbol!
        }
        private static let preflightCall = unsafeBitCast(
            tcc("TCCAccessPreflight"), to: Preflight.self)

        /// tccd's answer for this process: 0 allowed, 1 denied, else no record.
        private static func preflight(_ service: String) -> Int {
            preflightCall(service as CFString, nil)
        }
    }

    extension Permissions: Observable {}
#endif
