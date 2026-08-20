import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import SwiftUI

// The embedded-UI primitive: LAAuthenticationView pairs with ONE LAContext,
// and `evaluatePolicy` / `evaluateAccessControl` on that context renders the
// Touch ID (or Watch) affordance INSIDE this view instead of the system's
// floating alert - BUT ONLY IF the view is already installed in a window
// when the evaluation starts. Evaluate first and LocalAuthentication has no
// UI host paired yet, so it silently falls back to the standard alert (the
// exact popup this exists to kill; bit live on the first demo). So the host
// reports readiness from AppKit truth - viewDidMoveToWindow - and the OWNER
// starts evaluation only from that callback, never on its own clock.
//
// The view is non-textual by design (Apple's contract): the surrounding UI
// carries the reason. A context is single-use per attempt - re-arming means
// a fresh context AND a fresh view, so hosts recreate the sensor
// (`.id(attempt)`) rather than mutate it.
public struct DoorSensor: NSViewRepresentable {
    let context: LAContext
    let controlSize: NSControl.ControlSize
    let onReady: @MainActor () -> Void

    /// - Parameters:
    ///   - context: the LAContext this sensor renders for.
    ///   - onReady: fired ONCE, when the sensor is installed in a window -
    ///     the only correct moment to start evaluating on `context`.
    public init(
        context: LAContext,
        controlSize: NSControl.ControlSize = .regular,
        onReady: @escaping @MainActor () -> Void
    ) {
        self.context = context
        self.controlSize = controlSize
        self.onReady = onReady
    }

    public func makeNSView(context _: Context) -> SensorHost {
        SensorHost(context: context, controlSize: controlSize, onReady: onReady)
    }

    public func updateNSView(_: SensorHost, context _: Context) {}
}

// Hosts the system view, pins it, and sizes from ITS fitting size - a bare
// NSViewRepresentable can collapse to zero in SwiftUI, and a zero-sized
// sensor is another road to the fallback alert.
public final class SensorHost: NSView {
    private let sensor: LAAuthenticationView
    private let onReady: @MainActor () -> Void
    private var announced = false

    init(
        context: LAContext, controlSize: NSControl.ControlSize,
        onReady: @escaping @MainActor () -> Void
    ) {
        self.sensor = LAAuthenticationView(context: context, controlSize: controlSize)
        self.onReady = onReady
        super.init(frame: .zero)
        addSubview(sensor)
        sensor.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sensor.leadingAnchor.constraint(equalTo: leadingAnchor),
            sensor.trailingAnchor.constraint(equalTo: trailingAnchor),
            sensor.topAnchor.constraint(equalTo: topAnchor),
            sensor.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("SensorHost is code-only") }

    public override var intrinsicContentSize: NSSize { sensor.fittingSize }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !announced else { return }
        announced = true
        // One runloop hop: let the window finish installing the view before
        // the evaluation queries for its UI host.
        DispatchQueue.main.async { [onReady] in onReady() }
    }
}
