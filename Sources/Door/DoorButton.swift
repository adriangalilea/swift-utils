import LocalAuthentication
import SwiftUI

// A button whose press needs the person proven, one look on every device:
// the label says what the press does ("Book it"), and a small well inside the
// same capsule holds the proof's glyph, so it reads before anyone presses
// that this press is also a finger or a face.
//
// On a Mac the well IS the sensor: DoorField's in-field Touch ID, installed
// under the glyph, red and alive while armed (the system's own semantic for a
// live sensor), so a finger is the press and its proof in one gesture with no
// system dialog after it. The system sensor (`DoorSensor`) sits nearly
// invisible under the glyph: it must be in a window for Touch ID to render in
// place, and the host starts evaluating only from `onReady`. One context per
// attempt: a fresh context is a fresh sensor. A click stays a press; the host
// decides what it means while the sensor waits (point at it, or ask another
// way).
//
// On an iPhone no sensor lives in a view: the well holds Face ID's glyph, the
// press asks for Face ID as it goes, and `context` is never armed.
public struct DoorButton: View {
    let label: String
    let context: LAContext?
    let onReady: @MainActor (LAContext) -> Void
    let action: () -> Void

    /// - Parameters:
    ///   - label: what the press does.
    ///   - context: the armed context (a Mac's sensor waiting for a finger),
    ///     or nil: the glyph then marks that the press will ask for proof.
    ///   - onReady: the sensor is in a window: start evaluating on `context`.
    ///   - action: a click or a tap.
    public init(
        _ label: String, context: LAContext?, onReady: @escaping @MainActor (LAContext) -> Void = { _ in },
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
                ZStack {
                    #if os(macOS)
                        if let context {
                            DoorSensor(context: context, controlSize: .small) { onReady(context) }
                                .id(ObjectIdentifier(context))
                                .frame(width: 22, height: 22)
                                .opacity(0.02)
                                .allowsHitTesting(false)
                        }
                    #endif
                    Image(systemName: Self.glyph)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(armed ? AnyShapeStyle(Color.red.opacity(0.9)) : AnyShapeStyle(.white.opacity(0.85)))
                        .symbolEffect(.pulse, options: .repeating, isActive: armed)
                }
                .frame(width: 16, height: 16)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.black.opacity(0.22)))
            }
        }
        .buttonStyle(.borderedProminent)
        .help(armed ? "Rest your finger on Touch ID, or click" : "Asks for \(Self.proof)")
    }

    private var armed: Bool { context != nil }

    /// The device's own proof: Touch ID on a Mac, Face ID on an iPhone.
    static var glyph: String {
        #if os(macOS)
            "touchid"
        #else
            "faceid"
        #endif
    }
    static var proof: String {
        #if os(macOS)
            "Touch ID"
        #else
            "Face ID"
        #endif
    }
}
