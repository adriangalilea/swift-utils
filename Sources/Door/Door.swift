import LocalAuthentication
import Security
import SwiftUI

// In-window authentication, no popup. The shape Safari's locked private
// window proves: the WINDOW is the prompt - a glyph wearing the system's
// embedded fingerprint affordance, one title, one status line, an inline
// secret field. Resting a finger authorizes; typing is the ever-present
// fallback; nothing floats over the app.
//
// Why the popup exists elsewhere: reading a `.biometryCurrentSet` keychain
// item makes the KEYCHAIN run the system alert. Door owns the LAContext
// instead: it evaluates on a context paired with the embedded sensor (so
// the UI renders in-window) and hands the authorized context back - the
// consumer passes it to SecItemCopyMatching via kSecUseAuthenticationContext
// and the gated read succeeds with no second prompt (LAContext.h: "After
// successful access control evaluation, the LAContext can be used with
// keychain operations, so that they do not require user to authenticate").

/// What the door authorizes when a finger lands.
public enum DoorAsk {
    /// A plain policy gate (an app curtain with nothing keychain-bound).
    case policy(LAPolicy)
    /// A keychain access control (the `.biometryCurrentSet` item shape):
    /// evaluation renders in the sensor, and the returned context unlocks
    /// the item silently.
    case accessControl(SecAccessControl, LAAccessControlOperation)

    /// The default gate: Touch ID, or an authorized companion (Watch).
    public static var biometry: DoorAsk {
        .policy(.deviceOwnerAuthenticationWithBiometricsOrCompanion)
    }
}

/// How the door was passed.
public enum DoorVerdict {
    /// The sensor authorized: an evaluated context, ready for
    /// `kSecUseAuthenticationContext` keychain reads with no second prompt.
    case biometry(LAContext)
    /// The typed fallback secret. The CONSUMER verifies it - Door cannot.
    case secret(String)
}

/// The consumer's answer to a verdict. `.rejected` keeps the door up:
/// the message lands in the status slot (same slot, no layout shift),
/// a typed secret shakes the field and clears it.
public enum DoorJudgment {
    case accepted
    case rejected(String)
}

public struct Door: View {
    private let icon: String
    private let title: String
    private let subtitle: String
    private let inactiveSubtitle: String?
    private let prompt: String
    private let reason: String
    private let ask: DoorAsk
    private let backdrop: AnyShapeStyle
    private let judge: @MainActor (DoorVerdict) async -> DoorJudgment

    // One attempt = one fresh LAContext + one fresh sensor view (`.id`).
    // nil context = no biometry on this machine (or lockout downgraded it):
    // the sensor hides and the door is password-only, Safari-style.
    @State private var attempt = 0
    @State private var context: LAContext?
    @State private var note: String?
    @State private var secret = ""
    @State private var shakes = 0
    @State private var judging = false
    @FocusState private var fieldFocused: Bool
    // Safari couples the biometry affordance to KEY-WINDOW status: a
    // background window shows only the quiet lock (no sensor, no blue
    // ring, subtitle drops the Touch ID mention), and the sensor is
    // reborn on focus. Mirrored here via controlActiveState.
    @Environment(\.controlActiveState) private var activeState

    /// - Parameters:
    ///   - icon: SF Symbol for the door's glyph (the lock by default).
    ///   - title: what is locked ("Private Browsing Is Locked" register).
    ///   - subtitle: how to open it; also the fixed slot rejection
    ///     messages replace, so the layout never shifts.
    ///   - inactiveSubtitle: shown while the window is not key, when the
    ///     sensor is hidden - Safari drops the Touch ID mention there.
    ///     nil keeps the one subtitle.
    ///   - prompt: the secret field's placeholder.
    ///   - reason: the evaluation reason macOS requires (never shown by the
    ///     embedded sensor, but mandatory and user-visible in Settings).
    ///   - ask: what a successful touch authorizes (`.biometry` default).
    ///   - backdrop: the disc behind the fingerprint badge - pass the
    ///     surface the door sits on (a color OR a material), so the badge
    ///     reads as a cutout of the lock's corner (Safari's trick), never
    ///     a floating glyph.
    ///   - judge: receives every verdict; return `.accepted` to pass or
    ///     `.rejected(message)` to keep the door up. The consumer owns
    ///     dismissal - on `.accepted`, swap the door out of the hierarchy.
    public init(
        icon: String = "lock.fill",
        title: String,
        subtitle: String,
        inactiveSubtitle: String? = nil,
        prompt: String = "Enter password",
        reason: String,
        ask: DoorAsk = .biometry,
        backdrop: AnyShapeStyle = AnyShapeStyle(Color.black),
        judge: @escaping @MainActor (DoorVerdict) async -> DoorJudgment
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.inactiveSubtitle = inactiveSubtitle
        self.prompt = prompt
        self.reason = reason
        self.ask = ask
        self.backdrop = backdrop
        self.judge = judge
    }

    // Safari's grammar, measured off its locked-private-window screen: the
    // LOCK is the hero (a quiet grey glyph); the fingerprint is a small
    // badge OVERLAPPING its bottom-right corner on a backdrop disc that
    // matches the page, so it reads as a cutout of the lock, never a second
    // floating glyph. Then a 15pt bold title, 13pt quiet lines, and a slim
    // hand-drawn 28pt field - the stock rounded-border field is a fat box
    // with a thick focus ring and reads as trash next to Safari's.
    public var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(.tertiary)
                if let context, activeState != .inactive {
                    ZStack {
                        Circle().fill(backdrop)
                        // Evaluation starts ONLY from the sensor's onReady -
                        // it must already sit in the window or LA falls back
                        // to the floating system alert.
                        DoorSensor(context: context, controlSize: .small) {
                            startSensor(context)
                        }
                        .id(attempt)
                        .frame(width: 30, height: 30)
                    }
                    .frame(width: 42, height: 42)
                    .offset(x: 16, y: 10)
                    .onTapGesture { rearm() }
                }
            }
            .padding(.bottom, 18)

            Text(title)
                .font(.system(size: 15, weight: .bold))
                .padding(.bottom, 7)

            // ONE slot for subtitle and rejection notes: text swaps in
            // place, the reserved height never changes, nothing reflows.
            Text(note ?? (activeState == .inactive ? inactiveSubtitle ?? subtitle : subtitle))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 400, height: 32, alignment: .top)
                .padding(.bottom, 12)

            SecureField(prompt, text: $secret)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .frame(width: 240, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            fieldFocused && activeState != .inactive
                                ? Color.accentColor : Color.white.opacity(0.15),
                            lineWidth: fieldFocused && activeState != .inactive ? 2.5 : 1)
                )
                .focused($fieldFocused)
                .disabled(judging)
                .modifier(Shake(times: CGFloat(shakes)))
                .onSubmit { submitSecret() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            fieldFocused = true
            rearm()
        }
        .onChange(of: activeState) {
            if activeState == .inactive {
                // Background window: cancel the pending evaluation quietly
                // (invalidate lands in the .appCancel branch) and drop the
                // sensor; a fresh one is armed when focus returns.
                context?.invalidate()
                context = nil
            } else if context == nil {
                rearm()
            }
        }
    }

    // A fresh context + a reborn sensor view per attempt (the pairing is
    // per-context). Not called on cancel/failure automatically - the user
    // re-arms by touching the sensor glyph (or just types), never
    // surprised by a re-prompt.
    private func rearm() {
        let ctx = LAContext()
        ctx.localizedReason = reason
        guard
            ctx.canEvaluatePolicy(
                .deviceOwnerAuthenticationWithBiometricsOrCompanion, error: nil)
        else {
            context = nil
            return
        }
        attempt += 1
        context = ctx
    }

    // Fired by the sensor once it is INSTALLED in the window - the only
    // moment evaluation may begin (earlier and LA has no paired UI host,
    // and the floating alert comes back).
    private func startSensor(_ ctx: LAContext) {
        Task { await evaluate(ctx) }
    }

    private func evaluate(_ ctx: LAContext) async {
        do {
            switch ask {
            case .policy(let policy):
                try await ctx.evaluatePolicy(policy, localizedReason: reason)
            case .accessControl(let access, let operation):
                try await ctx.evaluateAccessControl(
                    access, operation: operation, localizedReason: reason)
            }
            await deliver(.biometry(ctx))
        } catch {
            sensorFailed(error)
        }
    }

    private func sensorFailed(_ error: Error) {
        switch (error as? LAError)?.code {
        case .userCancel, .systemCancel, .appCancel:
            // A cancel is the user's choice; stay quiet, don't re-prompt.
            break
        case .authenticationFailed:
            note =
                "Touch ID didn\u{2019}t match. Touch the sensor icon to retry, or type the password."
        case .biometryLockout:
            note = "Touch ID is locked. Type the password to continue."
            context = nil
        case .biometryNotAvailable, .biometryNotEnrolled, .biometryNotPaired, .passcodeNotSet:
            context = nil
        default:
            context = nil
        }
    }

    private func submitSecret() {
        let typed = secret
        guard !typed.isEmpty, !judging else { return }
        Task { await deliver(.secret(typed)) }
    }

    private func deliver(_ verdict: DoorVerdict) async {
        judging = true
        defer { judging = false }
        switch await judge(verdict) {
        case .accepted:
            break  // the consumer swaps the door away
        case .rejected(let message):
            note = message
            if case .secret = verdict {
                secret = ""
                withAnimation(.default) { shakes += 1 }
                fieldFocused = true
            }
        }
    }
}

// The rejection shake: a damped horizontal wobble, geometry-only, so the
// field trembles in place and the composition never reflows.
private struct Shake: GeometryEffect {
    var times: CGFloat
    var animatableData: CGFloat {
        get { times }
        set { times = newValue }
    }
    func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: 8 * sin(times * .pi * 4), y: 0))
    }
}
