import Door
import SwiftUI

// Door's demo: the Safari-private-mode shape over sample content, live.
// `swift run door-example` - a resting finger authorizes (real Touch ID,
// in-window, no system alert), or type the demo password "sesame". A wrong
// secret shakes in place; the status slot swaps text without reflow.

struct DemoView: View {
    @State private var open = false

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
                }
            } else {
                Door(
                    title: "This Demo Is Locked",
                    subtitle: "Touch ID or type \u{201c}sesame\u{201d} to open the demo.",
                    inactiveSubtitle: "Type \u{201c}sesame\u{201d} to open the demo.",
                    reason: "unlock the door demo"
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
        WindowGroup("door demo") {
            DemoView()
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}

// A bare SPM executable is a .prohibited-policy process: its window exists
// but the app cannot be activated or brought forward. Declare regular.
NSApplication.shared.setActivationPolicy(.regular)
DemoApp.main()
