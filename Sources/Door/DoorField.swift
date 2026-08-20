import AppKit
import LocalAuthentication
import SwiftUI

// The compact form of Door: secret-entry FIELDS with the biometric door
// built in, for sheets where the window cannot be the prompt. Same rules
// as the curtain: the fingerprint is a live embedded sensor (a resting
// finger authorizes - no click, no floating system alert), typing is the
// ever-present fallback, and state changes animate in place.

// The one field container: every secret-entry surface wears this box, so
// SecretField and DoorField's authorized state can't drift apart.
struct SecretBox: ViewModifier {
    let border: Color
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(border, lineWidth: 1))
            .animation(.snappy(duration: 0.15), value: border)
    }
}

/// A password field with a reveal toggle. `trailing` is the accessory slot
/// beside the eye (DoorField puts the sensor there).
public struct SecretField<Trailing: View>: View {
    let prompt: String
    @Binding var text: String
    // .newPassword → the OS offers "Suggest Strong Password" + password-manager
    // AutoFill (1Password et al. participate as the system provider). .password
    // → AutoFill an existing one. nil → no AutoFill.
    var contentType: NSTextContentType?
    // nil = no validation chrome; true/false = green/attention border once typing.
    var valid: Bool?
    @ViewBuilder var trailing: () -> Trailing
    @State private var visible = false

    public init(
        prompt: String, text: Binding<String>,
        contentType: NSTextContentType? = .password, valid: Bool? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.prompt = prompt
        self._text = text
        self.contentType = contentType
        self.valid = valid
        self.trailing = trailing
    }

    private var border: Color {
        guard let valid, !text.isEmpty else { return .secondary.opacity(0.25) }
        return valid ? .green.opacity(0.8) : .orange.opacity(0.55)
    }

    public var body: some View {
        HStack(spacing: 6) {
            Group {
                if visible {
                    TextField(prompt, text: $text)
                } else {
                    SecureField(prompt, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .textContentType(contentType)
            if valid == true {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
            Button {
                visible.toggle()
            } label: {
                Image(systemName: visible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(visible ? "hide" : "show")
            trailing()
        }
        .modifier(SecretBox(border: border))
        .animation(.snappy(duration: 0.15), value: valid)
    }
}

extension SecretField where Trailing == EmptyView {
    public init(
        prompt: String, text: Binding<String>,
        contentType: NSTextContentType? = .password, valid: Bool? = nil
    ) {
        self.init(
            prompt: prompt, text: text, contentType: contentType,
            valid: valid, trailing: { EmptyView() })
    }
}

/// The authorization field: a SecretField with the biometric door built in.
/// Two ways to authorize: type the secret (the caller resolves what it is),
/// or REST A FINGER - the trailing slot holds a live embedded sensor
/// (DoorSensor), armed while the window is key, so authorization needs no
/// click and raises no system alert. On a successful touch the field calls
/// `unlock` with the evaluated context (keychain reads through
/// `kSecUseAuthenticationContext` prompt nothing); a non-nil Key locks the
/// field into the authorized state, undoable back to typing. Pass
/// `door: nil` where only a typed secret counts.
public struct DoorField<Key>: View {
    let prompt: String
    @Binding var text: String
    @Binding var key: Key?  // set = the biometric door passed
    let door: (reason: String, unlock: @MainActor (LAContext) -> Key?)?

    // One attempt = one fresh context + one reborn sensor, exactly Door's
    // machinery: evaluation starts only from the sensor's in-window
    // readiness, cancels quietly, hides while the window is not key.
    @State private var attempt = 0
    @State private var context: LAContext?
    @Environment(\.controlActiveState) private var activeState

    public init(
        prompt: String, text: Binding<String>, key: Binding<Key?>,
        door: (reason: String, unlock: @MainActor (LAContext) -> Key?)? = nil
    ) {
        self.prompt = prompt
        self._text = text
        self._key = key
        self.door = door
    }

    public var body: some View {
        Group {
            if key != nil {
                HStack(spacing: 6) {
                    Image(systemName: "touchid").foregroundStyle(.green)
                    Text("authorized with touch id").foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        key = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("type the secret instead")
                }
                .modifier(SecretBox(border: .green.opacity(0.8)))
            } else {
                SecretField(prompt: prompt, text: $text) {
                    if let context, activeState != .inactive {
                        DoorSensor(context: context, controlSize: .small) {
                            startSensor(context)
                        }
                        .id(attempt)
                        .frame(width: 20, height: 20)
                        .help("rest a finger to authorize")
                        .onTapGesture { rearm() }
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.15), value: key != nil)
        .onAppear { rearm() }
        .onChange(of: activeState) {
            if activeState == .inactive {
                context?.invalidate()
                context = nil
            } else if context == nil {
                rearm()
            }
        }
        .onChange(of: key == nil) {
            // Undo (x) re-opens the door: a fresh sensor arms for the next touch.
            if key == nil { rearm() } else { context = nil }
        }
    }

    private func rearm() {
        guard door != nil, key == nil else {
            context = nil
            return
        }
        let ctx = LAContext()
        // Biometrics ONLY (no Watch): the door typically guards a
        // .biometryCurrentSet keychain item, which a companion evaluation
        // would not satisfy - the read would throw the system alert this
        // component exists to kill.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        else {
            context = nil
            return
        }
        attempt += 1
        context = ctx
    }

    private func startSensor(_ ctx: LAContext) {
        guard let door else { return }
        ctx.localizedReason = door.reason
        Task {
            do {
                try await ctx.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics, localizedReason: door.reason)
                if let unlocked = door.unlock(ctx) {
                    key = unlocked
                    text = ""
                }
            } catch {
                // Cancel or mismatch: stay in the typed state, quietly.
                // Touching the sensor re-arms (rearm via tap).
            }
        }
    }
}
