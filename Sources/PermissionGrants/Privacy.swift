#if os(macOS)
    import AVFoundation
    import AppKit
    import ApplicationServices
    import CoreMotion
    import Log
    import Observation
    import Speech
    import Synchronization

    private let grantLog = log.scope("grant")

    extension PermissionGrant {
        /// The Privacy & Security switches a grant reads, named for what they
        /// let an app do. The raw value is tccd's service name.
        public enum Privacy: String, Sendable, CaseIterable {
            /// The AX API: read and act on other apps' interfaces.
            case accessibility = "kTCCServiceAccessibility"
            /// Post keyboard and mouse events (typing into other apps);
            /// System Settings lists it under Accessibility.
            case postEvents = "kTCCServicePostEvent"
            /// Listen to the keyboard, write its LEDs ("Input Monitoring").
            case inputMonitoring = "kTCCServiceListenEvent"
            /// Record what the Mac plays (a Core Audio process tap, "System
            /// Audio Recording"). Apple ships no public check or ask for it.
            case systemAudio = "kTCCServiceAudioCapture"
            /// Capture the screen ("Screen & System Audio Recording").
            case screenRecording = "kTCCServiceScreenCapture"
            case microphone = "kTCCServiceMicrophone"
            case camera = "kTCCServiceCamera"
            /// Speech recognition through Apple's recognizer.
            case speechRecognition = "kTCCServiceSpeechRecognition"
            /// Headphone motion (AirPods head tracking), "Motion & Fitness".
            case motion = "kTCCServiceMotion"
            /// Every file, including other apps' data. macOS has no prompt
            /// for it: the person adds the app in the pane.
            case fullDiskAccess = "kTCCServiceSystemPolicyAllFiles"

            /// macOS enforces the switch on a running app at once, even while
            /// that app's own check answers as of its launch: grant-example
            /// typed into TextEdit right after Accessibility was switched on
            /// (2026-10-21). Input Monitoring and Screen Recording are not:
            /// macOS itself asks for "Quit & Reopen". Unmeasured switches stay
            /// on the reopen side.
            var appliesLive: Bool {
                switch self {
                case .accessibility, .postEvents: true
                case .inputMonitoring, .systemAudio, .screenRecording, .microphone, .camera,
                    .speechRecognition, .motion, .fullDiskAccess:
                    false
                }
            }

            /// The name in logs.
            var title: String {
                switch self {
                case .accessibility: "Accessibility"
                case .postEvents: "Posting events"
                case .inputMonitoring: "Input Monitoring"
                case .systemAudio: "System Audio Recording"
                case .screenRecording: "Screen Recording"
                case .microphone: "Microphone"
                case .camera: "Camera"
                case .speechRecognition: "Speech Recognition"
                case .motion: "Motion"
                case .fullDiskAccess: "Full Disk Access"
                }
            }

            /// The pane's name in System Settings › Privacy & Security.
            var paneTitle: String {
                switch self {
                case .accessibility, .postEvents: "Accessibility"
                case .inputMonitoring: "Input Monitoring"
                case .systemAudio, .screenRecording: "Screen & System Audio Recording"
                case .microphone: "Microphone"
                case .camera: "Camera"
                case .speechRecognition: "Speech Recognition"
                case .motion: "Motion & Fitness"
                case .fullDiskAccess: "Full Disk Access"
                }
            }

            /// The pane's deep-link anchor.
            var pane: String {
                switch self {
                case .accessibility, .postEvents: "Privacy_Accessibility"
                case .inputMonitoring: "Privacy_ListenEvent"
                case .systemAudio: "Privacy_AudioCapture"
                case .screenRecording: "Privacy_ScreenCapture"
                case .microphone: "Privacy_Microphone"
                case .camera: "Privacy_Camera"
                case .speechRecognition: "Privacy_SpeechRecognition"
                case .motion: "Privacy_Motion"
                case .fullDiskAccess: "Privacy_AllFiles"
                }
            }

            var symbol: String {
                switch self {
                case .accessibility: "accessibility"
                case .postEvents: "keyboard"
                case .inputMonitoring: "keyboard.badge.eye"
                case .systemAudio: "speaker.wave.2"
                case .screenRecording: "rectangle.dashed.badge.record"
                case .microphone: "mic"
                case .camera: "camera"
                case .speechRecognition: "waveform"
                case .motion: "airpods.pro"
                case .fullDiskAccess: "externaldrive"
                }
            }
        }
    }

    /// The live Privacy & Security answers of this app, ONE hub every grant
    /// reads.
    ///
    /// What macOS tells a running app is as of its launch. Asked about itself,
    /// a process gets tccd's answer as it stood when the process started, for
    /// a switch flipped later as for a revoked one (Accessibility read
    /// "denied" while macOS already let grant-example type; the microphone
    /// read "allowed" after it was reset; 2026-10-21), and the public checks
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
    ///   switch, grants and revocations alike. Where macOS enforces the
    ///   switch on the running app at once (`appliesLive`) the fresh answer
    ///   is the answer; where it does not, a fresh "allowed" is
    ///   `allowedOnReopen`. An app without the probe (`answerProbeIfAsked`
    ///   missing from its main) is read in-process in the window instead.
    ///
    /// A change publishes through Observation (a view that read it repaints)
    /// and to every `observe` handler, and is logged with its source and raw
    /// code (scope `grant`; `grant status <app>` prints the latest).
    final class PrivacyHub: @unchecked Sendable {
        typealias Privacy = PermissionGrant.Privacy
        static let shared = PrivacyHub()

        /// What macOS answers for one switch.
        enum Answer: String, Sendable, Equatable {
            case allowed, denied
            /// No record: the person was never asked (or it was reset).
            case notAsked = "not asked"
            /// Allowed in System Settings, not usable by this running process
            /// until it reopens.
            case allowedOnReopen = "allowed on reopen"
            /// The source cannot see it (System Audio Recording on the public
            /// APIs: Apple ships no check for it).
            case unknown
        }

        /// The one mapping from an answer to what every surface shows.
        func standing(_ privacy: Privacy) -> PermissionGrant.Standing {
            switch answer(privacy) {
            case .allowed: .good
            case .allowedOnReopen: .broken("Reopen", note: "Allowed. Applies when the app reopens.")
            case .unknown: .unknown(note: "macOS doesn't tell apps this one.")
            case .notAsked: .askable("Allow\u{2026}")
            case .denied:
                .broken(
                    "Open Settings\u{2026}",
                    note: "Off in Privacy & Security › \(privacy.paneTitle).")
            }
        }

        // MARK: The source, chosen once

        /// Where every reading comes from, chosen ONCE at launch and never
        /// mixed, so no two surfaces can read from different places:
        /// - `tccd`: TCC.framework's `TCCAccessPreflight` (private): tccd's
        ///   own tri-state for every switch.
        /// - `publicAPI`: what Apple documents (`AXIsProcessTrusted`,
        ///   `CGPreflight…`, AVFoundation's status). The fallback for an OS
        ///   without the private call: never-asked and denied look alike
        ///   until this run's first ask, System Audio is `.unknown`.
        /// `GRANT_PUBLIC_API=1` in the environment forces the fallback, so it
        /// is exercised, never dead code.
        enum Source: String, Sendable {
            case tccd
            case publicAPI = "public API"
        }

        static let source: Source = {
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
        static func code(_ privacy: Privacy) -> Int {
            switch source {
            case .tccd: preflightCall!(privacy.rawValue as CFString, nil)
            case .publicAPI: publicCode(privacy)
            }
        }

        /// Switches asked in this run: on the public APIs, the one way to
        /// tell "never asked" from "denied" (both read false).
        private static let asked = Mutex<Set<Privacy>>([])

        private static func publicCode(_ privacy: Privacy) -> Int {
            let wasAsked = asked.withLock { $0.contains(privacy) }
            let granted: Bool
            switch privacy {
            case .accessibility: granted = AXIsProcessTrusted()
            case .postEvents: granted = CGPreflightPostEventAccess()
            case .inputMonitoring: granted = CGPreflightListenEventAccess()
            case .screenRecording: granted = CGPreflightScreenCaptureAccess()
            case .systemAudio, .fullDiskAccess: return -1
            case .microphone: return capture(AVCaptureDevice.authorizationStatus(for: .audio))
            case .camera: return capture(AVCaptureDevice.authorizationStatus(for: .video))
            case .speechRecognition:
                switch SFSpeechRecognizer.authorizationStatus() {
                case .authorized: return 0
                case .notDetermined: return 2
                default: return 1
                }
            case .motion:
                switch CMHeadphoneMotionManager.authorizationStatus() {
                case .authorized: return 0
                case .notDetermined: return 2
                default: return 1
                }
            }
            return granted ? 0 : wasAsked ? 1 : 2
        }

        private static func capture(_ status: AVAuthorizationStatus) -> Int {
            switch status {
            case .authorized: 0
            case .notDetermined: 2
            default: 1
            }
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
        private var answers: [Privacy: Answer] = [:]
        private var handlers: [UUID: (Privacy, Answer) -> Void] = [:]
        private let queue = DispatchQueue(label: "grant.privacy", qos: .utility)
        private var started = false
        /// Bumped on every change: what Observation tracks.
        private var revision = 0

        private init() {}

        /// The current answer. The first read of a switch asks now, on the
        /// calling thread, and starts watching it.
        func answer(_ privacy: Privacy) -> Answer {
            registrar.access(self, keyPath: \.revision)
            if let known = lock.withLock({ answers[privacy] }) { return known }
            startIfNeeded()
            let code = Self.code(privacy)
            return record(privacy, Self.answer(code: code), raw: code, fresh: false)
        }

        /// `handler` runs on the main thread with every change of any watched
        /// switch (never for an unchanged reading).
        @discardableResult
        func observe(_ handler: @escaping (Privacy, Answer) -> Void) -> UUID {
            let token = UUID()
            lock.withLock { handlers[token] = handler }
            return token
        }

        /// Until when the hub reads, every 2 s.
        private static let settingsWindow = Mutex(Date.distantPast)

        /// The person may be changing permissions now (an ask, a pane opened,
        /// the app back in front, macOS announcing an Accessibility change):
        /// read at once, then every 2 s for two minutes.
        func watchSettings(_ why: String) {
            let opened = Self.settingsWindow.withLock { until in
                defer { until = Date().addingTimeInterval(120) }
                return Date() >= until
            }
            // Logged when it opens, so what keeps a hub busy is never a guess.
            if opened { grantLog.info("watching for permission changes", ["why": why]) }
            queue.async { [self] in readAll() }
        }

        /// Every watched switch, from a fresh process when the app has the
        /// probe, else in-process.
        private func readAll() {
            let watched = lock.withLock { Array(answers.keys) }
            guard !watched.isEmpty else { return }
            let fresh = Self.freshCodes()
            for privacy in watched {
                let own = Self.code(privacy)
                guard let new = fresh?[privacy] else {
                    record(privacy, Self.answer(code: own), raw: own, fresh: false)
                    continue
                }
                let answer: Answer =
                    new == 0 && own != 0 && !privacy.appliesLive
                    ? .allowedOnReopen : Self.answer(code: new)
                record(privacy, answer, raw: new, fresh: true)
            }
        }

        @discardableResult
        private func record(_ privacy: Privacy, _ answer: Answer, raw: Int, fresh: Bool) -> Answer {
            let (changed, first) = lock.withLock { () -> (Bool, Bool) in
                let old = answers[privacy]
                answers[privacy] = answer
                return (old != answer, old == nil)
            }
            guard changed else { return answer }
            grantLog.info(
                first ? "reads \(answer.rawValue)" : "changed to \(answer.rawValue)",
                [
                    "grant": privacy.title, "service": privacy.rawValue, "code": raw,
                    "source": Self.source.rawValue + (fresh ? ", fresh process" : ""),
                ])
            registrar.withMutation(of: self, keyPath: \.revision) {
                lock.withLock { revision += 1 }
            }
            if !first {
                let current = lock.withLock { Array(handlers.values) }
                DispatchQueue.main.async { for handler in current { handler(privacy, answer) } }
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

        // MARK: Asking

        /// Every ask the same way. Allowed: nothing. Allowed on reopen: the
        /// app reopens. Denied: the pane opens (the only place it can change;
        /// macOS never prompts twice). Otherwise the app comes forward (macOS
        /// asks only an active app: from a menu bar panel that never activates
        /// it, the request made no record and no prompt, 2026-10-18) and the
        /// request is made, the person's answer recorded when a prompt gives
        /// one. Then the hub watches: the person may be flipping the switch.
        @MainActor func ask(_ privacy: Privacy) async {
            let before = answer(privacy)
            switch before {
            case .allowed:
                return
            case .allowedOnReopen:
                return Self.reopen()
            case .denied:
                grantLog.info("asked again: opening its pane", ["grant": privacy.title])
                Self.openSettings(pane: privacy.pane)
            case .notAsked, .unknown:
                // A command-line tool has no NSApp, and nothing to bring forward.
                NSApp?.activate()
                Self.asked.withLock { _ = $0.insert(privacy) }
                let answered = await Self.request(privacy)
                grantLog.info(
                    "asked macOS",
                    [
                        "grant": privacy.title, "before": before.rawValue,
                        "answered": answered.map { $0 ? "allowed" : "denied" }
                            ?? "in System Settings",
                    ])
                if let answered {
                    record(
                        privacy, answered ? .allowed : .denied, raw: answered ? 0 : 1, fresh: false)
                }
            }
            watchSettings("asked")
        }

        /// The request for each switch, by one rule: Apple's public ask where
        /// one exists, TCC.framework's where none does, the pane where macOS
        /// has no prompt at all. The person's answer when a prompt gives one,
        /// nil when the answer is a switch in System Settings.
        @MainActor private static func request(_ privacy: Privacy) async -> Bool? {
            switch privacy {
            case .screenRecording:
                _ = CGRequestScreenCaptureAccess()
                return nil
            case .camera:
                if Signature.hardened, !Signature.entitled("com.apple.security.device.camera") {
                    grantLog.error(
                        "the camera can never be granted: the hardened runtime needs com.apple.security.device.camera in this app's entitlements, and macOS denies without asking"
                    )
                }
                return await AVCaptureDevice.requestAccess(for: .video)
            case .speechRecognition:
                return await withCheckedContinuation { done in
                    SFSpeechRecognizer.requestAuthorization {
                        done.resume(returning: $0 == .authorized)
                    }
                }
            case .fullDiskAccess:
                openSettings(pane: privacy.pane)
                return nil
            case .motion:
                // CoreMotion asks only when headphones start streaming; no
                // AirPods, no prompt. tccd's own ask prompts either way.
                return await privateRequest(privacy)
            case .accessibility:
                // kAXTrustedCheckOptionPrompt by value: Swift 6 rejects the C
                // global as shared mutable state, and the string is ABI-frozen.
                _ = AXIsProcessTrustedWithOptions(
                    ["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                return nil
            case .postEvents:
                _ = CGRequestPostEventAccess()
                return nil
            case .inputMonitoring:
                // The route WindowServer takes to tccd. `IOHIDRequestAccess`
                // from a menu bar app never reached tccd (2026-10-18).
                _ = CGRequestListenEventAccess()
                return nil
            case .microphone:
                // Under the hardened runtime macOS denies without asking unless
                // the signature carries the audio-input entitlement
                // (grant-example, 2026-10-21: asked and denied in one instant).
                if Signature.hardened, !Signature.entitled("com.apple.security.device.audio-input")
                {
                    grantLog.error(
                        "the microphone can never be granted: the hardened runtime needs com.apple.security.device.audio-input in this app's entitlements, and macOS denies without asking"
                    )
                }
                return await AVCaptureDevice.requestAccess(for: .audio)
            case .systemAudio:
                return await privateRequest(privacy)
            }
        }

        /// `TCCAccessRequest`: prompts with the app's usage description when
        /// no record exists, answers at once when one does. Without it the
        /// pane is the one place left to grant the switch.
        @MainActor private static func privateRequest(_ privacy: Privacy) async -> Bool? {
            guard let symbol = tcc("TCCAccessRequest") else {
                openSettings(pane: privacy.pane)
                return nil
            }
            let call = unsafeBitCast(symbol, to: Request.self)
            return await withCheckedContinuation { done in
                call(privacy.rawValue as CFString, nil) { done.resume(returning: $0) }
            }
        }

        /// Opens a new instance of this app, then quits this one: what makes
        /// an allowed-on-reopen switch count. macOS's own "Quit & Reopen"
        /// quit grant-example and never opened it again (2026-10-21).
        @MainActor static func reopen() {
            let open = NSWorkspace.OpenConfiguration()
            open.createsNewApplicationInstance = true
            grantLog.info("reopening to apply a permission")
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: open) {
                _, error in
                if let error {
                    grantLog.error("reopen failed", ["err": error])
                    return
                }
                Task { @MainActor in NSApp?.terminate(nil) }
            }
        }

        /// A Privacy & Security pane ("Privacy_Accessibility", …).
        static func openSettings(pane: String) {
            grantLog.info("opened System Settings", ["pane": pane])
            shared.watchSettings("pane opened")
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        }

        // MARK: The fresh process

        static func answerProbeIfAsked() {
            if CommandLine.arguments.contains(probeFlag) {
                for privacy in Privacy.allCases { print(privacy.rawValue, code(privacy)) }
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

        /// Every switch's code as a NEW process of this app sees it, or nil
        /// (no probe in this app, no disclaim, or the probe failed).
        private static func freshCodes() -> [Privacy: Int]? {
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
            // Typed: Xcode 26's solver reads the literal as strdup's pointers.
            let words: [String] = [executable, probeFlag]
            let argv: [UnsafeMutablePointer<CChar>?] = words.map { strdup($0) } + [nil]
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
            var codes: [Privacy: Int] = [:]
            for line in String(decoding: output, as: UTF8.self).split(separator: "\n") {
                let parts = line.split(separator: " ")
                guard parts.count == 2, let privacy = Privacy(rawValue: String(parts[0])),
                    let code = Int(parts[1])
                else { continue }
                codes[privacy] = code
            }
            guard codes.count == Privacy.allCases.count else {
                grantLog.warn("fresh probe answered \(codes.count) of \(Privacy.allCases.count)")
                return nil
            }
            return codes
        }

        // MARK: TCC.framework

        private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
        private typealias Request =
            @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

        /// A TCC.framework function, or nil (an OS without it: the public
        /// APIs take over, `source`).
        private static func tcc(_ name: String) -> UnsafeMutableRawPointer? {
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

    extension PrivacyHub: Observable {}

    /// Privacy & Security › Automation: Apple Events to one target app. Not on
    /// the hub (tccd keys it by target), and its answer is CACHED PER PROCESS:
    /// after Allow the running app keeps reading the pre-decision value until
    /// relaunch (live-verified), so the blocking ask's own answer is kept here
    /// and trusted over the stale check.
    enum Automation {
        private static let sessionGranted = Mutex<Set<String>>([])

        static func allowed(_ bundleID: String) -> Bool? {
            if sessionGranted.withLock({ $0.contains(bundleID) }) { return true }
            var addr = AEAddressDesc()
            let created = bundleID.data(using: .utf8)!.withUnsafeBytes {
                AECreateDesc(typeApplicationBundleID, $0.baseAddress, $0.count, &addr)
            }
            guard created == noErr else { return nil }
            defer { AEDisposeDesc(&addr) }
            switch AEDeterminePermissionToAutomateTarget(&addr, typeWildCard, typeWildCard, false) {
            case noErr: return true
            case OSStatus(errAEEventWouldRequireUserConsent), OSStatus(procNotFound): return nil
            default: return false
            }
        }

        static func standing(of bundleID: String) -> PermissionGrant.Standing {
            switch allowed(bundleID) {
            case true?: .good
            case nil: .askable("Allow\u{2026}")
            case false?:
                .broken("Open Settings\u{2026}", note: "Off in Privacy & Security › Automation.")
            }
        }

        /// The official ask: `AEDeterminePermissionToAutomateTarget` with
        /// askUserIfNeeded raises the system prompt itself and BLOCKS until
        /// the person answers, so it runs off the main thread. The prompt
        /// needs the `com.apple.security.automation.apple-events` entitlement
        /// under the hardened runtime. Once denied, the pane opens.
        @MainActor static func ask(_ bundleID: String) async {
            guard allowed(bundleID) != false else {
                return PrivacyHub.openSettings(pane: "Privacy_Automation")
            }
            NSApp?.activate()
            let verdict = await Task.detached(priority: .userInitiated) { () -> OSStatus in
                var addr = AEAddressDesc()
                let created = bundleID.data(using: .utf8)!.withUnsafeBytes {
                    AECreateDesc(typeApplicationBundleID, $0.baseAddress, $0.count, &addr)
                }
                guard created == noErr else { return OSStatus(created) }
                defer { AEDisposeDesc(&addr) }
                return AEDeterminePermissionToAutomateTarget(
                    &addr, typeWildCard, typeWildCard, true)
            }.value
            grantLog.info(
                "asked macOS", ["grant": "Automation of \(bundleID)", "status": Int(verdict)])
            if verdict == noErr { sessionGranted.withLock { _ = $0.insert(bundleID) } }
        }
    }

    /// This process's own signature: what macOS weighs before it asks.
    enum Signature {
        /// Signed with the hardened runtime (where a missing device
        /// entitlement is a silent denial).
        static var hardened: Bool {
            var code: SecCode?
            guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
            var staticCode: SecStaticCode?
            guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode
            else { return false }
            var info: CFDictionary?
            guard
                SecCodeCopySigningInformation(
                    staticCode, SecCSFlags(rawValue: kSecCSDynamicInformation), &info)
                    == errSecSuccess,
                let flags = (info as? [String: Any])?[kSecCodeInfoFlags as String] as? UInt32
            else { return false }
            return flags & SecCodeSignatureFlags.runtime.rawValue != 0
        }

        static func entitled(_ key: String) -> Bool {
            guard let task = SecTaskCreateFromSelf(nil) else { return false }
            return SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? Bool == true
        }
    }
#endif
