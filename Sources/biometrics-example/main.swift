import Biometrics
import SwiftUI

// The Biometrics demo: the Safari-private-mode lock over sample content, live.
// `swift run biometrics-example` - a resting finger authorizes (real Touch ID,
// in-window, no system alert), or type the demo password "sesame". A wrong
// secret shakes in place; the status slot swaps text without reflow.

struct DemoView: View {
    @State private var open = false
    @State private var fieldSecret = ""
    @State private var fieldKey: String?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            if open {
                VStack(spacing: 12) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("open").font(.title2.weight(.semibold))
                    Button("lock again") { open = false }
                    Divider().frame(width: 280).padding(.vertical, 8)
                    Text("the compact form: BiometricField").font(.caption).foregroundStyle(.secondary)
                    BiometricField(
                        prompt: "type the secret",
                        text: $fieldSecret, key: $fieldKey,
                        biometric: BiometricUnlock(reason: "authorize the demo field") { _ in "authorized" }
                    )
                    Text("a press a finger can make: BiometricButton").font(.caption).foregroundStyle(.secondary)
                    BiometricButton("Open it", context: nil) { open = true }
                    .frame(width: 280)
                }
            } else {
                BiometricLock(
                    title: "This Demo Is Locked",
                    subtitle: "Touch ID or type \u{201c}sesame\u{201d} to open the demo.",
                    inactiveSubtitle: "Type \u{201c}sesame\u{201d} to open the demo.",
                    reason: "unlock the biometrics demo"
                ) { verdict in
                    switch verdict {
                    case .biometry:
                        open = true
                        return .accepted
                    case .secret(let typed) where typed == "sesame":
                        open = true
                        return .accepted
                    case .secret:
                        return .rejected("That wasn\u{2019}t it. Hint: sesame.")
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

struct DemoApp: App {
    var body: some Scene {
        WindowGroup("biometrics demo") {
            DemoView()
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}

// A bare SPM executable is a .prohibited-policy process: its window exists
// but the app cannot be activated or brought forward. Declare regular.
NSApplication.shared.setActivationPolicy(.regular)
DemoApp.main()
