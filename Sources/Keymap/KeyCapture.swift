import AppKit
import SwiftUI

/// THE capture-next-combo mechanism - the grid's recording pill and the
/// panel's recording chip are skins over this one monitor. Swallows every
/// key while armed: ⎋ cancels, an unresolvable key is ignored, anything
/// else resolves to a KeyCombo and lands in `onCombo` - whose verdict
/// (true = done, false = keep listening; the store's rejection keeps the
/// session alive so the user can try another key) drives the session.
@MainActor
final class KeyCapture {
    private var monitor: Any?

    init(onCombo: @escaping (KeyCombo) -> Bool, onCancel: @escaping () -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 {  // esc
                    onCancel()
                } else if let combo = KeyCombo(event: event) {
                    _ = onCombo(combo)
                }
            }
            return nil  // armed = every key belongs to the capture
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
