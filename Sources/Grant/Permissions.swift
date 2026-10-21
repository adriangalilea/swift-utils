#if os(macOS)
    import AVFoundation
    import AppKit
    import ApplicationServices
    import Log
    import Observation
    import Synchronization

    private let grantLog = log.scope("grant")

    /// The live permissions of this app, ONE hub every surface and every
    /// check reads.
    ///
    /// What macOS tells a running app is as of its launch. Asked about itself,
    /// a process gets tccd's answer as it stood when the process started, for
    /// a switch flipped later as for a revoked one (Accessibility read
    /// "denied" while macOS already let grant-example type; the microphone
    /// read "allowed" after it was reset; 2026-10-21), and the public probes
    /// (`AXIsProcessTrusted`, `CGPreflight…`) are no better. The truth after
    /// a change lives only in a NEW process. So:
    ///
    /// - **First read**: synchronous, in this process (a surface's first frame
    ///   is the truth: at launch the two agree).
    /// - **Idle otherwise.** Nothing is read while nothing can change.
    /// - **The settings window**: two minutes after the app comes forward, an
    ///   ask, a pane opened, or macOS announcing an Accessibility change (a
    ///   switch only flips while the person is in System Settings). Every 2 s
    ///   in it, ONE fresh process of the app's own binary (`--grant-probe`,
    ///   spawned disowned so tccd judges it as itself) answers every watched
    ///   permission, grants and revocations alike. Where macOS enforces the
    ///   switch on the running app at once (`appliesLive`) the fresh answer
    ///   is the answer; where it does not, a fresh "allowed" is
    ///   `allowedOnReopen`. An app without the probe (`answerProbeIfAsked`
    ///   missing from its main) is read in-process in the window instead.
    ///
    /// A change publishes through Observation (a view that read it repaints)
    /// and to every `observe` handler, and is logged with its source and raw
    /// code (scope `grant`; `grant status <app>` prints the latest).
    public final class Permissions: @unchecked Sendable {
        public static let shared = Permissions()

        /// What macOS answers for one of this app's permissions. Nested:
        /// "Answer" is every app's word for its own things (Authz's voice
        /// card, perceive's questions), never this library's to take.
        public enum Answer: String, Sendable, Equatable {
            case allowed, denied
            /// No record: the person was never asked (or it was reset).
            case notAsked = "not asked"
            /// Allowed in System Settings, not usable by this running process
            /// until it reopens (Input Monitoring: macOS's own "Quit & Reopen").
            case allowedOnReopen = "allowed on reopen"
            /// The source cannot see it (System Audio Recording on the public
            /// APIs: Apple ships no check for it).
            case unknown
        }

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
            /// that app's own check answers as of its launch: grant-example
            /// typed into TextEdit right after Accessibility was switched on
            /// (2026-10-21). Input Monitoring is not: macOS itself asks for
            /// "Quit & Reopen". Unmeasured services stay on the relaunch side.
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

        // MARK: The source, chosen once

        /// Where every reading comes from, chosen ONCE at launch and never
        /// mixed, so no two surfaces can read from different places:
        /// - `tccd`: TCC.framework's `TCCAccessPreflight` (private): tccd's
        ///   own tri-state for every service.
        /// - `publicAPI`: what Apple documents (`AXIsProcessTrusted`,
        ///   `CGPreflight…`, AVFoundation's status). The fallback for an OS
        ///   without the private call: never-asked and denied look alike
        ///   until this run's first ask, System Audio is `.unknown`.
        /// `GRANT_PUBLIC_API=1` in the environment forces the fallback, so it
        /// is exercised, never dead code.
        public enum Source: String, Sendable {
            case tccd
            case publicAPI = "public API"
        }

        public static let source: Source = {
            if ProcessInfo.processInfo.environment["GRANT_PUBLIC_API"] == "1" {
                grantLog.warn("readings from the public APIs (GRANT_PUBLIC_API=1)")
                return .publicAPI
            }
            guard preflightCall != nil else {
                grantLog.error(
                    "TCCAccessPreflight is gone from TCC.framework: readings fall back to the public APIs"
                )
                return .publicAPI
            }
            return .tccd
        }()

        /// This process's raw answer from the source: 0 allowed, 1 denied,
        /// 2 no record, -1 the source cannot see it.
        static func code(_ service: Service) -> Int {
            switch source {
            case .tccd: preflightCall!(service.rawValue as CFString, nil)
            case .publicAPI: publicCode(service)
            }
        }

        /// Services asked in this run: on the public APIs, the one way to
        /// tell "never asked" from "denied" (both read false).
        private static let asked = Mutex<Set<Service>>([])
        static func noteAsked(_ service: Service) { asked.withLock { _ = $0.insert(service) } }

        private static func publicCode(_ service: Service) -> Int {
            let wasAsked = asked.withLock { $0.contains(service) }
            let granted: Bool
            switch service {
            case .accessibility: granted = AXIsProcessTrusted()
            case .postEvents: granted = CGPreflightPostEventAccess()
            case .inputMonitoring: granted = CGPreflightListenEventAccess()
            case .systemAudio: return -1
            case .microphone:
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized: return 0
                case .notDetermined: return 2
                default: return 1
                }
            }
            return granted ? 0 : wasAsked ? 1 : 2
        }

        static func answer(code: Int) -> Answer {
            switch code {
            case 0: .allowed
            case 1: .denied
            case -1: .unknown
            default: .notAsked
            }
        }

        // MARK: Reading

        private let registrar = ObservationRegistrar()
        private let lock = NSLock()
        private var answers: [Service: Answer] = [:]
        private var handlers: [UUID: (Service, Answer) -> Void] = [:]
        private let queue = DispatchQueue(label: "grant.permissions", qos: .utility)
        private var started = false
        /// Bumped on every change: what Observation tracks.
        private var revision = 0

        private init() {}

        /// The current answer. The first read of a service asks now, on the
        /// calling thread, and starts watching it.
        public func answer(_ service: Service) -> Answer {
            registrar.access(self, keyPath: \.revision)
            if let known = lock.withLock({ answers[service] }) { return known }
            startIfNeeded()
            let code = Self.code(service)
            return record(service, Self.answer(code: code), raw: code, fresh: false)
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

        /// Until when the hub reads, every 2 s.
        private static let settingsWindow = Mutex(Date.distantPast)

        /// The person may be changing permissions now (an ask, a pane opened,
        /// the app back in front, macOS announcing an Accessibility change):
        /// read at once, then every 2 s for two minutes.
        public func watchSettings(_ why: String = "asked") {
            let opened = Self.settingsWindow.withLock { until in
                defer { until = Date().addingTimeInterval(120) }
                return Date() >= until
            }
            // Logged when it opens, so what keeps a hub busy is never a guess.
            if opened { grantLog.info("watching for permission changes", ["why": why]) }
            queue.async { [self] in readAll() }
        }

        /// Every watched service, from a fresh process when the app has the
        /// probe, else in-process.
        private func readAll() {
            let services = lock.withLock { Array(answers.keys) }
            guard !services.isEmpty else { return }
            let fresh = Self.freshCodes()
            for service in services {
                let own = Self.code(service)
                guard let new = fresh?[service] else {
                    record(service, Self.answer(code: own), raw: own, fresh: false)
                    continue
                }
                let answer: Answer =
                    new == 0 && own != 0 && !service.appliesLive
                    ? .allowedOnReopen : Self.answer(code: new)
                record(service, answer, raw: new, fresh: true)
            }
        }

        @discardableResult
        private func record(_ service: Service, _ answer: Answer, raw: Int, fresh: Bool) -> Answer {
            let (changed, first) = lock.withLock { () -> (Bool, Bool) in
                let old = answers[service]
                answers[service] = answer
                return (old != answer, old == nil)
            }
            guard changed else { return answer }
            grantLog.info(
                first ? "reads \(answer.rawValue)" : "changed to \(answer.rawValue)",
                [
                    "grant": service.title, "service": service.rawValue, "code": raw,
                    "source": Self.source.rawValue + (fresh ? ", fresh process" : ""),
                ])
            registrar.withMutation(of: self, keyPath: \.revision) {
                lock.withLock { revision += 1 }
            }
            if !first {
                let current = lock.withLock { Array(handlers.values) }
                DispatchQueue.main.async { for handler in current { handler(service, answer) } }
            }
            return answer
        }

        private var timer: DispatchSourceTimer?

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
                guard Self.settingsWindow.withLock({ Date() < $0 }) else { return }
                readAll()
            }
            timer.resume()
            self.timer = timer
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.watchSettings("app came forward") }
            // Posted by macOS when the Accessibility list changes.
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: nil
            ) { [weak self] _ in self?.watchSettings("macOS: Accessibility changed") }
        }

        // MARK: The fresh process

        /// A probe launch answers and exits: the app's `main` calls this
        /// before anything else. Without it the hub reads in-process, as of
        /// launch, and a change shows only when the app reopens.
        public static func answerProbeIfAsked() {
            if CommandLine.arguments.contains(probeFlag) {
                for service in Service.allCases { print(service.rawValue, code(service)) }
                exit(0)
            }
            probes.withLock { $0 = true }
        }

        private static let probeFlag = "--grant-probe"
        /// Set once the app's main called `answerProbeIfAsked`: only then is
        /// its binary a probe (otherwise running it launches the app).
        private static let probes = Mutex(false)

        private typealias Disclaim =
            @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
        /// libsystem's responsibility SPI, how Xcode launches an app as
        /// itself: a child is otherwise judged through its parent, whose
        /// answer is the stale one. Missing, the probe is off (logged once).
        private static let disclaim: Disclaim? = {
            guard
                let symbol = dlsym(
                    UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim"
                )
            else {
                grantLog.error(
                    "responsibility_spawnattrs_setdisclaim is gone: no fresh probe, changes show on reopen"
                )
                return nil
            }
            return unsafeBitCast(symbol, to: Disclaim.self)
        }()

        /// Every service's code as a NEW process of this app sees it, or nil
        /// (no probe in this app, no disclaim, or the probe failed).
        private static func freshCodes() -> [Service: Int]? {
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
            let argv = [executable, probeFlag].map { strdup($0) } + [nil]
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
            var codes: [Service: Int] = [:]
            for line in String(decoding: output, as: UTF8.self).split(separator: "\n") {
                let parts = line.split(separator: " ")
                guard parts.count == 2, let service = Service(rawValue: String(parts[0])),
                    let code = Int(parts[1])
                else { continue }
                codes[service] = code
            }
            guard codes.count == Service.allCases.count else {
                grantLog.warn("fresh probe answered \(codes.count) of \(Service.allCases.count)")
                return nil
            }
            return codes
        }

        // MARK: TCC.framework

        private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
        typealias Request =
            @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

        /// A TCC.framework function, or nil (an OS without it: the public
        /// APIs take over, `source`).
        static func tcc(_ name: String) -> UnsafeMutableRawPointer? {
            guard
                let handle = dlopen(
                    "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
            else { return nil }
            return dlsym(handle, name)
        }
        private static let preflightCall: Preflight? = tcc("TCCAccessPreflight").map {
            unsafeBitCast($0, to: Preflight.self)
        }
    }

    extension Permissions: Observable {}
#endif
