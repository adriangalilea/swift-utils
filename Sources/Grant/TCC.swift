#if os(macOS)
    import AVFoundation
    import AppKit
    import ApplicationServices
    import Log

    private let grantLog = log.scope("grant")

    /// The TCC probes and requests, each answering the tri-state a Standing
    /// derives from: true = granted, false = denied, nil = never asked. Every
    /// probe reads `Permissions` (tccd itself, never a remembered answer);
    /// every ask is logged (scope `grant`) beside the readings it changes.
    ///
    /// One bundle id, one record, one signature: tccd binds a grant to the
    /// code requirement of the build that received it. A Developer ID
    /// release and an Apple Development build of the same app do not share
    /// it: utter's switch showed ON in System Settings while tccd answered
    /// "Denied (Service Policy)", the record belonging to a Developer ID build
    /// long gone (2026-10-20). `tccutil reset <service> <bundle id>` clears it;
    /// the next ask records the running build.
    public enum TCC {
        // The AE permission answer is CACHED PER PROCESS: after the user
        // clicks Allow, the running app keeps reading the pre-decision
        // value until relaunch (live-verified: TCC recorded allow while
        // the UI stayed grey). The blocking ask RETURNS the user's
        // decision, so the request records it here and the probe trusts
        // it over the stale cache.
        nonisolated(unsafe) private static var sessionGranted: Set<String> = []
        // kAXTrustedCheckOptionPrompt by value: Swift 6 rejects the C
        // global as shared mutable state, and the string is ABI-frozen
        // (TCC compatibility) since 10.9.
        private static let axPromptOption = "AXTrustedCheckOptionPrompt"

        private static func reading(_ service: Permissions.Service) -> Bool? {
            switch Permissions.shared.answer(service) {
            case .allowed: true
            case .denied: false
            case .notAsked: nil
            }
        }

        /// Every ask the same way: bring the app forward (macOS asks only an
        /// active app: from a menu bar panel that never activates it, the
        /// request made no record and no prompt, 2026-10-18), make the
        /// request (with no record it prompts and lists the app; with one it
        /// is silent), open the pane when the person already said no (the
        /// only place it can change), and read again as the answer lands.
        private static func ask(
            _ service: Permissions.Service, pane: String, _ request: () -> Bool
        ) {
            let before = Permissions.shared.answer(service)
            guard before != .allowed else { return }
            // An ask is a person's click (or a command line's first use):
            // the main thread, or a bug. A command-line tool has no NSApp,
            // and nothing to bring forward.
            MainActor.assumeIsolated { NSApp?.activate() }
            let allowed = request()
            grantLog.info(
                "asked macOS",
                ["grant": service.title, "before": before.rawValue, "allowed": allowed])
            if before == .denied { openSettings(pane: pane) }
            Permissions.shared.refreshSoon()
        }

        // MARK: Accessibility (the AX API grant)

        public static func accessibility() -> Bool? { reading(.accessibility) }

        public static func requestAccessibility() {
            ask(.accessibility, pane: "Privacy_Accessibility") {
                AXIsProcessTrustedWithOptions([axPromptOption: true] as CFDictionary)
            }
        }

        // MARK: Posting events (typing into other apps)

        /// Whether this process may post keyboard events. macOS lists it
        /// under Accessibility.
        public static func postEvents() -> Bool? { reading(.postEvents) }

        public static func requestPostEvents() {
            ask(.postEvents, pane: "Privacy_Accessibility") { CGRequestPostEventAccess() }
        }

        // MARK: Input Monitoring (listen to the keyboard, light its LEDs)

        public static func inputMonitoring() -> Bool? { reading(.inputMonitoring) }

        /// `CGRequestListenEventAccess`, the route WindowServer takes to
        /// tccd. `IOHIDRequestAccess` from a menu bar app never reached tccd
        /// (no request in its log, 2026-10-18), so it is not used.
        public static func requestInputMonitoring() {
            ask(.inputMonitoring, pane: "Privacy_ListenEvent") { CGRequestListenEventAccess() }
        }

        // MARK: System Audio Recording (a process tap)

        /// No public probe or ask exists for it (AudioCap's finding); a tap
        /// without it records silence with no error, so this is the only way
        /// an app knows.
        public static func systemAudio() -> Bool? { reading(.systemAudio) }

        /// `TCCAccessRequest`: prompts with no record; a denial is changed in
        /// the pane only. `answered` runs on the main thread with the
        /// person's answer to the prompt (at once, false, when no prompt can
        /// show: already denied, or already allowed).
        public static func requestSystemAudio(
            answered: (@MainActor @Sendable (Bool) -> Void)? = nil
        ) {
            guard Permissions.shared.answer(.systemAudio) == .notAsked else {
                ask(.systemAudio, pane: "Privacy_AudioCapture") { false }
                let allowed = Permissions.shared.answer(.systemAudio) == .allowed
                MainActor.assumeIsolated { answered?(allowed) }
                return
            }
            ask(.systemAudio, pane: "Privacy_AudioCapture") {
                let request = unsafeBitCast(
                    Permissions.tcc("TCCAccessRequest"), to: Permissions.Request.self)
                request(Permissions.Service.systemAudio.rawValue as CFString, nil) { allowed in
                    Permissions.shared.refreshSoon()
                    Task { @MainActor in answered?(allowed) }
                }
                return false
            }
        }

        // MARK: Microphone

        public static func microphone() -> Bool? { reading(.microphone) }

        /// AVFoundation's ask (the prompt quotes the app's
        /// NSMicrophoneUsageDescription).
        public static func requestMicrophone(answered: (@MainActor @Sendable (Bool) -> Void)? = nil)
        {
            ask(.microphone, pane: "Privacy_Microphone") {
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    Permissions.shared.refreshSoon()
                    Task { @MainActor in answered?(allowed) }
                }
                return false
            }
            if Permissions.shared.answer(.microphone) != .notAsked {
                let allowed = Permissions.shared.answer(.microphone) == .allowed
                MainActor.assumeIsolated { answered?(allowed) }
            }
        }

        // MARK: Automation (Apple Events to one target app)

        public static func automation(of bundleID: String) -> Bool? {
            if sessionGranted.contains(bundleID) { return true }
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

        /// The OFFICIAL ask: AEDeterminePermissionToAutomateTarget with
        /// askUserIfNeeded=true raises the system consent prompt itself
        /// (AppleEvents.h, 10.14+) - no scripting, no fake event. It
        /// BLOCKS until the user decides, so it runs off-main. NOTE: the
        /// prompt can only appear with the
        /// com.apple.security.automation.apple-events entitlement -
        /// hardened runtime silently kills AEs without it. Once denied,
        /// deep-links System Settings instead.
        public static func requestAutomation(of bundleID: String) {
            guard automation(of: bundleID) != false else {
                return openSettings(pane: "Privacy_Automation")
            }
            DispatchQueue.global(qos: .userInitiated).async {
                var addr = AEAddressDesc()
                let created = bundleID.data(using: .utf8)!.withUnsafeBytes {
                    AECreateDesc(typeApplicationBundleID, $0.baseAddress, $0.count, &addr)
                }
                guard created == noErr else { return }
                defer { AEDisposeDesc(&addr) }
                let verdict = AEDeterminePermissionToAutomateTarget(
                    &addr, typeWildCard, typeWildCard, true)
                grantLog.info(
                    "asked macOS", ["grant": "Automation of \(bundleID)", "status": Int(verdict)])
                if verdict == noErr {
                    DispatchQueue.main.async { sessionGranted.insert(bundleID) }
                }
            }
        }

        // MARK: System Settings

        /// Privacy & Security pane deep link ("Privacy_Accessibility",
        /// "Privacy_Automation", …).
        public static func openSettings(pane: String) {
            grantLog.info("opened System Settings", ["pane": pane])
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        }
    }
#endif
