import LocalAuthentication
import SwiftUI

// A button whose press can be a finger: DoorField's in-field sensor, inside
// a prominent button. The label says what the press does ("Book it"); a small
// well inside the same capsule holds the Touch ID glyph and says "rest a
// finger here", red while the sensor is armed (the system's own semantic for a live
// sensor), so the finger IS the press and its proof in one gesture, with no
// system dialog after it. A click is still a press: the host decides what a
// click means while the sensor waits (point at it, or ask another way).
//
// The system sensor (`DoorSensor`) is installed nearly invisible under the
// glyph: it must be in a window for Touch ID to render in place rather than
// as the floating alert, and the host starts evaluating only from its
// `onReady`. One context per attempt: a fresh context is a fresh sensor.
public struct DoorButton: View {
    let label: String
    let context: LAContext?
    let onReady: @MainActor (LAContext) -> Void
    let action: () -> Void

    /// - Parameters:
    ///   - label: what the press does.
    ///   - context: the armed context, or nil when no sensor waits (no Touch
    ///     ID here, or between attempts): the glyph then reads as the plain
    ///     "this needs you proven" mark.
    ///   - onReady: the sensor is in a window: start evaluating on `context`.
    ///   - action: a click.
    public init(
        _ label: String, context: LAContext?, onReady: @escaping @MainActor (LAContext) -> Void,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.context = context
        self.onReady = onReady
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                // The sensor's well: a small inset in the button, its own
                // place to rest a finger, the way DoorField's sits in the field.
                ZStack {
                    if let context {
                        DoorSensor(context: context, controlSize: .small) { onReady(context) }
                            .id(ObjectIdentifier(context))
                            .frame(width: 22, height: 22)
                            .opacity(0.02)
                            .allowsHitTesting(false)
                    }
                    Image(systemName: "touchid")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(context != nil ? AnyShapeStyle(Color.red.opacity(0.9)) : AnyShapeStyle(.white.opacity(0.8)))
                        .symbolEffect(.pulse, options: .repeating, isActive: context != nil)
                }
                .frame(width: 16, height: 16)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.black.opacity(0.22)))
            }
        }
        .buttonStyle(.borderedProminent)
        .help(context != nil ? "Rest your finger on Touch ID, or click" : "Needs Touch ID")
    }
}
