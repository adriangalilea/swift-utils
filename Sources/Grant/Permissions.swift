#if os(macOS)
    import AppKit
    import Log
    import Observation
    import Synchronization

    private let grantLog = log.scope("grant")

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

        /// What macOS answers for one of this app's permissions, asked of
        /// tccd itself. Nested: "Answer" is every app's word for its own
        /// things (Authz's voice card, perceive's questions), never this
        /// library's to take.
        public enum Answer: String, Sendable, Equatable {
            case allowed, denied
            /// No record: the person was never asked (or it was reset).
            case notAsked = "not asked"
            /// Allowed in System Settings, not for this process: tccd answers
            /// a running app as it stood at launch for some services (Input
            /// Monitoring, Accessibility: macOS's own "Quit & Reopen"). A new
            /// process of the same app reads it allowed (`answerProbeIfAsked`).
            case allowedOnReopen = "allowed on reopen"
        }

        /// A probe launch answers and exits: the app's `main` calls this
        /// before anything else. The hub runs the app's own binary as a fresh
        /// process (disowned, so tccd judges it as itself, never through this
        /// running one) to learn what System Settings says now; without this
        /// call it never does, and a switch flipped after launch reads denied
        /// until the app reopens.
        public static func answerProbeIfAsked() {
            let args = CommandLine.arguments
            if let at = args.firstIndex(of: probeFlag), at + 1 < args.count {
                print(preflight(args[at + 1]))
                exit(0)
            }
            probes.withLock { $0 = true }
        }

        private static let probeFlag = "--grant-probe"

        /// Until when a denied permission is checked against a fresh process.
        private static let settingsWindow = Mutex(Date.distantPast)

        /// The person may be flipping switches now (an ask, a pane opened,
        /// the app back in front): for two minutes, denied permissions are
        /// checked against a fresh process, then re-read at once.
        public func watchSettings() {
            Self.settingsWindow.withLock { $0 = Date().addingTimeInterval(120) }
            refreshSoon()
        }
        /// Set once the app's main called `answerProbeIfAsked`: only then is
        /// its binary a probe (otherwise running it launches the app).
        private static let probes = Mutex(false)

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

            /// macOS enforces the switch on a running app at once, even while
            /// tccd still answers that app's preflight as of its launch:
            /// grant-example typed into TextEdit right after Accessibility was
            /// switched on, its in-process answer still "denied" (2026-10-21).
            /// Input Monitoring is not: macOS itself asks for "Quit & Reopen".
            /// Unmeasured services stay on the relaunch side.
            var appliesLive: Bool {
                switch self {
                case .accessibility, .postEvents: true
                case .inputMonitoring, .systemAudio, .microphone: false
                }
            }

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
            var answer: Answer =
                switch code {
                case 0: .allowed
                case 1: .denied
                default: .notAsked
                }
            // Denied for this process: does System Settings say so too? A
            // switch only flips while the person is in System Settings, so a
            // fresh process is asked only in the window after an ask, a pane
            // opened or the app coming forward (`watchSettings`), never every
            // 2 s for a permission declined for good.
            if answer == .denied, Self.settingsWindow.withLock({ Date() < $0 }),
                Self.fresh(service) == 0
            {
                answer = service.appliesLive ? .allowed : .allowedOnReopen
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
                let now = answer
                DispatchQueue.main.async { for handler in current { handler(service, now) } }
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
            ) { [weak self] _ in self?.watchSettings() }
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

        private typealias Disclaim =
            @convention(c) (
                UnsafeMutablePointer<posix_spawnattr_t?>, Int32
            ) -> Int32
        /// libsystem's responsibility SPI, how Xcode launches an app as
        /// itself: a child is otherwise judged through its parent, whose
        /// answer is the stale one.
        private static let disclaim: Disclaim? = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim"
        ).map { unsafeBitCast($0, to: Disclaim.self) }

        /// tccd's answer for a NEW process of this app (the app's binary with
        /// `--grant-probe`), or nil when the app has no probe (its main does
        /// not call `answerProbeIfAsked`) or the probe failed.
        private static func fresh(_ service: Service) -> Int? {
            guard probes.withLock({ $0 }), let disclaim,
                let executable = Bundle.main.executableURL?.path
            else { return nil }
            var attr: posix_spawnattr_t?
            posix_spawnattr_init(&attr)
            defer { posix_spawnattr_destroy(&attr) }
            guard disclaim(&attr, 1) == 0 else { return nil }
            var actions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&actions)
            defer { posix_spawn_file_actions_destroy(&actions) }
            var pipe: [Int32] = [0, 0]
            guard Darwin.pipe(&pipe) == 0 else { return nil }
            posix_spawn_file_actions_adddup2(&actions, pipe[1], STDOUT_FILENO)
            posix_spawn_file_actions_addclose(&actions, pipe[0])
            let argv = [executable, probeFlag, service.rawValue].map { strdup($0) } + [nil]
            defer { argv.forEach { free($0) } }
            var pid: pid_t = 0
            let spawned = posix_spawn(&pid, executable, &actions, &attr, argv, environ)
            close(pipe[1])
            defer { close(pipe[0]) }
            guard spawned == 0 else {
                grantLog.warn("fresh probe did not start", ["errno": spawned])
                return nil
            }
            let output = FileHandle(fileDescriptor: pipe[0]).readDataToEndOfFile()
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            return Int(
                String(decoding: output, as: UTF8.self).trimmingCharacters(
                    in: .whitespacesAndNewlines))
        }
    }

    extension Permissions: Observable {}
#endif
