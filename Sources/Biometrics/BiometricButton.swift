import Ink
import LocalAuthentication
import SwiftUI

// A button whose press needs biometrics, one look on every device: Ink's
// prominent capsule (it keeps its color whether or not its window holds the
// keyboard), the label saying what the press does ("Book it"), and a round
// well at the trailing cap, concentric with it, holding the biometric glyph,
// so it reads before anyone presses that this press is also a finger or a
// face. The host's `.tint` colors it.
//
// On a Mac the well IS the sensor: BiometricField's in-field Touch ID,
// installed under the glyph, the glyph alive (pulsing) while armed, so a
// finger is the press and its proof in one gesture with no system dialog
// after it. The system sensor (`BiometricSensor`) sits nearly
// invisible under the glyph: it must be in a window for Touch ID to render in
// place, and the host starts evaluating only from `onReady`. One context per
// attempt: a fresh context is a fresh sensor. A click stays a press; the host
// decides what it means while the sensor waits (point at it, or ask another
// way).
//
// On an iPhone no sensor lives in a view: the well holds Face ID's glyph, the
// press asks for Face ID as it goes, and `context` is never armed.
public struct BiometricButton: View {
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
        _ label: String, context: LAContext?,
        onReady: @escaping @MainActor (LAContext) -> Void = { _ in },
        action: @escaping () -> Void
    ) {
        self.label = label
        self.context = context
        self.onReady = onReady
        self.action = action
    }

    /// The well's diameter: the capsule's height less an inset of 4 on
    /// every side, so its circle is concentric with the cap's.
    static let well = InkButtonStyle.height - 8

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                ZStack {
                    #if os(macOS)
                        if let context {
                            BiometricSensor(context: context, controlSize: .small) {
                                onReady(context)
                            }
                            .id(ObjectIdentifier(context))
                            .frame(width: Self.well, height: Self.well)
                            .opacity(0.02)
                            .allowsHitTesting(false)
                        }
                    #endif
                    Image(systemName: Self.glyph)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(armed ? 1 : 0.8))
                        .symbolEffect(.pulse, options: .repeating, isActive: armed)
                }
                .frame(width: Self.well, height: Self.well)
                .background(Circle().fill(.white.opacity(0.16)))
            }
        }
        // The cap's inset on the trailing edge is the well's own: 4.
        .buttonStyle(InkButtonStyle(.prominent, trailing: 4))
        .inkTip(armed ? "Rest your finger on Touch ID, or click" : "Asks for \(Self.proof)")
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
