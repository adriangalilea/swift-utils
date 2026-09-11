import SwiftUI

// MediaSpec's gate + demo. `--check` pins the shared vocabulary literals,
// the label rules, the provenance order and the lenient-decode law, and
// exits nonzero on the first violation. Without the flag: a window on
// black with every chip variant - the visual sweep the operator judges
// (never a PNG).

if CommandLine.arguments.contains("--check") {
    runChecks()  // never returns
}
DemoApp.main()
