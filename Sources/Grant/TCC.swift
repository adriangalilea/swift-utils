#if os(macOS)
    import AppKit
    import ApplicationServices

    /// The TCC probe + request primitives, each answering the tri-state a
    /// Standing derives from: true = granted, false = denied, nil = never
    /// asked. Hard-won corners live here so no app re-learns them.
    public enum TCC {
        // The AE permission answer is CACHED PER PROCESS: after the user
        // clicks Allow, the running app keeps reading the pre-decision
        // value until relaunch (live-verified: TCC recorded allow while
        // the UI stayed grey). The blocking ask RETURNS the user's
        // decision, so the request records it here and the probe trusts
        // it over the stale cache.
        nonisolated(unsafe) private static var sessionGranted: Set<String> = []
        private static let promptedKey = "grant.accessibilityPrompted"
        // kAXTrustedCheckOptionPrompt by value: Swift 6 rejects the C
        // global as shared mutable state, and the string is ABI-frozen
        // (TCC compatibility) since 10.9.
        private static let axPromptOption = "AXTrustedCheckOptionPrompt"

        // MARK: Accessibility (the AX API grant)

        public static func accessibility() -> Bool? {
            if AXIsProcessTrusted() { return true }
            return UserDefaults.standard.bool(forKey: promptedKey) ? false : nil
        }

        /// First ask fires the system prompt; once denied, only System
        /// Settings can flip it (macOS never re-prompts), so ask again and
        /// this deep-links there.
        public static func requestAccessibility() {
            guard accessibility() != false else {
                return openSettings(pane: "Privacy_Accessibility")
            }
            let opts = [axPromptOption: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            UserDefaults.standard.set(true, forKey: promptedKey)
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
                if verdict == noErr {
                    DispatchQueue.main.async { sessionGranted.insert(bundleID) }
                }
            }
        }

        // MARK: System Settings

        /// Privacy & Security pane deep link ("Privacy_Accessibility",
        /// "Privacy_Automation", …).
        public static func openSettings(pane: String) {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        }
    }
#endif
