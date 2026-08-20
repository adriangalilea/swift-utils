import AppKit
import LocalAuthentication
import SwiftUI

// The compact form of Door: secret-entry FIELDS with the biometric door
// built in, for sheets where the window cannot be the prompt. Presentation
// is hollow's original styled box + 1Password's accessory grammar (quiet
// eye, hairline, quiet fingerprint - Adrian-matched); the MECHANIC is the
// curtain's: armed all the time, a resting finger authorizes in place.
// The system sensor view refuses affordance sizes (renders huge or not at
// all), so the PAIRING and the AFFORDANCE are split: a static touchid
// glyph is what you see, and the paired LAAuthenticationView sits over it
// at natural size, visually silent (opacity ~0) but in the window - which
// is all LocalAuthentication requires for embedded evaluation. Clicking
// the glyph is the fallback for anyone who doesn't discover the rest
// gesture: a plain unpaired evaluation, i.e. the classic system prompt.
// KNOWN LIMIT: no animation DURING the read - LocalAuthentication exposes
// no finger-landed signal, only completion; the recognized-bounce and the
// wrong-finger shake are the feedback (Adrian: "good for now").

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
            // Accessories stay QUIET (Adrian, matched against 1Password's
            // field): small tertiary glyphs, the text owns the field.
            Button {
                visible.toggle()
            } label: {
                Image(systemName: visible ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
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

/// The biometric door a DoorField opens: why (the evaluation reason) and
/// what a passed evaluation unlocks. A struct, not a tuple: the first real
/// consumer proved an inline tuple+closure defeats the type checker, and a
/// nominal type anchors inference so call sites stay inline:
///
///     DoorField(prompt: "password", text: $text, key: $key,
///               door: hasTouchID ? DoorUnlock(reason: "unlock the vault") { ctx in
///                   try? fetchKey(context: ctx)
///               } : nil)
public struct DoorUnlock<Key> {
    let reason: String
    let unlock: @MainActor (LAContext) -> Key?

    public init(reason: String, unlock: @escaping @MainActor (LAContext) -> Key?) {
        self.reason = reason
        self.unlock = unlock
    }
}

/// The authorization field: a SecretField with the biometric door built in.
/// Three ways through: type the secret (the caller resolves what it is),
/// REST A FINGER (embedded evaluation, armed while the window is key, no
/// click, no alert), or click the fingerprint (the classic system prompt,
/// for anyone who does not discover the rest gesture). On success the field
/// calls `door.unlock` with the evaluated context - keychain reads through
/// `kSecUseAuthenticationContext` prompt nothing - and a non-nil Key locks
/// the field into the authorized state, undoable back to typing. Pass
/// `door: nil` where only a typed secret counts.
public struct DoorField<Key>: View {
    let prompt: String
    @Binding var text: String
    @Binding var key: Key?  // set = the biometric door passed
    let door: DoorUnlock<Key>?

    @State private var attempt = 0
    @State private var context: LAContext?
    @State private var shakes = 0  // wrong finger: the curtain's shake, in place
    @State private var recognized = 0  // right finger: one bounce as it goes green
    @Environment(\.controlActiveState) private var activeState

    public init(
        prompt: String, text: Binding<String>, key: Binding<Key?>,
        door: DoorUnlock<Key>? = nil
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
                    Image(systemName: "touchid")
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: recognized)
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
                    if door != nil {
                        Divider().frame(height: 13)
                        ZStack {
                            if let context, activeState != .inactive {
                                DoorSensor(context: context, controlSize: .small) {
                                    startSensor(context)
                                }
                                .id(attempt)
                                .frame(width: 28, height: 28)
                                .opacity(0.02)
                                .allowsHitTesting(false)
                            }
                            Button {
                                clickFallback()
                            } label: {
                                // RED while armed - the sensor's own semantic
                                // (the curtain's live fingerprint), so "rest a
                                // finger here" reads without words. Grey =
                                // no live sensor (click for the prompt).
                                Image(systemName: "touchid")
                                    .font(.system(size: 13))
                                    .foregroundStyle(
                                        context != nil && activeState != .inactive
                                            ? AnyShapeStyle(Color.red.opacity(0.8))
                                            : AnyShapeStyle(.secondary))
                            }
                            .buttonStyle(.plain)
                            .help("rest a finger, or click to authorize")
                        }
                        .frame(width: 16, height: 16)
                        .modifier(Shake(times: CGFloat(shakes)))
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
        guard door != nil, key == nil, activeState != .inactive else {
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
                    recognized += 1
                    key = unlocked
                    text = ""
                }
            } catch {
                // Wrong finger: the curtain's shake, then a fresh sensor so
                // the next rest works. Cancels stay quiet and un-rearmed
                // (deactivation invalidates; the active-state change re-arms).
                if (error as? LAError)?.code == .authenticationFailed {
                    withAnimation(.default) { shakes += 1 }
                    rearm()
                }
            }
        }
    }

    // The dense-user path: a fresh UNPAIRED context, so the system shows
    // its classic prompt. Also re-arms the ambient sensor afterwards.
    private func clickFallback() {
        guard let door else { return }
        context?.invalidate()
        context = nil
        let ctx = LAContext()
        ctx.localizedReason = door.reason
        Task {
            defer { rearm() }
            do {
                try await ctx.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics, localizedReason: door.reason)
                if let unlocked = door.unlock(ctx) {
                    recognized += 1
                    key = unlocked
                    text = ""
                }
            } catch {}
        }
    }
}
