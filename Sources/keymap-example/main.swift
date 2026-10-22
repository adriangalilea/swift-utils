import AppKit
import SwiftUI

// Keymap's which-key tips without an app. `--check` runs the laws headless and
// exits nonzero on any violation: the completion rule per prefix and the tip
// placement rule. Without the flag: a window with tipped controls along every
// edge and in the middle; `?` toggles the bare reveal, held modifiers reveal
// their layers, ⌃⌥⌘/ the global forms (from any app).

if CommandLine.arguments.contains("--check") {
    runChecks()  // never returns
}
NSApplication.shared.setActivationPolicy(.regular)
DemoApp.main()
