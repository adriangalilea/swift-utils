import SwiftUI

// Gallery's gate + demo. `--check` runs the kernel invariants headless and
// exits nonzero on the first violation (the runnable-example testing
// stance: no test suite, a gate you can also look at). Without the flag: a
// demo window - 200 synthetic aspects through the real GalleryView with
// the keyboard walk and selection grammar wired the way a host app would.

if CommandLine.arguments.contains("--check") {
    runChecks()  // never returns
}
DemoApp.main()
