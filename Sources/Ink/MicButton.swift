import SwiftUI

// THE mic affordance, designed once: a push-to-talk button with the
// messaging-app interaction grammar and a live spectrum while hot.
//
// Interaction grammar (Telegram's, the one everyone's hands already know):
//   - press and HOLD  -> capture runs while held, release stops it
//   - quick TAP       -> capture latches on (a lock badge says so),
//                        the next tap stops it
// The discrimination lives in `PushToTalk`, one state machine consumed by
// the button's gesture AND any key binding (press/release), so pointer and
// keyboard can never drift apart.
//
// The audio itself is not this component's business: feed it a spectrum
// provider (0-1 band magnitudes) and a voice-activity flag - in the studio
// both come from listen's `AudioSpectrum` over a `MicCapture`
// (github.com/adriangalilea/listen). This file owns the FEEL; listen owns
// the signal.

/// The tap-vs-hold state machine. `pressBegan`/`pressEnded` from any input
/// (pointer, a hotkey's down/up); `engaged` is the one truth consumers
/// observe to start/stop capture.
@MainActor
public final class PushToTalk: ObservableObject {
    @Published public private(set) var engaged = false
    /// Engaged via a quick tap: stays on until the next tap. false while
    /// engaged means a hold is in progress and release will stop.
    @Published public private(set) var latched = false

    /// Presses shorter than this latch; longer ones are holds.
    public var holdThreshold: TimeInterval = 0.35
    /// The side-effect seam: start capture on true, stop on false.
    public var onChange: ((Bool) -> Void)?

    private var pressedAt: Date?
    private var stopOnRelease = false

    public init() {}

    public func pressBegan() {
        if engaged {
            // Tapping a latched (or held-elsewhere) capture arms the stop;
            // it lands on release so a hold-started-while-engaged cannot
            // flap.
            stopOnRelease = true
            return
        }
        pressedAt = Date()
        engaged = true
        latched = false
        onChange?(true)
    }

    public func pressEnded() {
        defer { pressedAt = nil }
        if stopOnRelease {
            stopOnRelease = false
            disengage()
            return
        }
        guard engaged, let pressedAt else { return }
        if Date().timeIntervalSince(pressedAt) < holdThreshold {
            latched = true
        } else {
            disengage()
        }
    }

    /// External cancel (focus lost, an error, the consumer's own policy).
    public func stop() { disengage() }

    private func disengage() {
        guard engaged else { return }
        engaged = false
        latched = false
        onChange?(false)
    }
}

#if os(macOS)
    /// The button. Idle: a quiet circle with the mic glyph and its keycap
    /// hint. Engaged: the circle turns recording-red and a spectrum capsule
    /// unfolds beside it - live band magnitudes, bright while voice is
    /// detected, dim over silence, so "is it hearing ME" is answered by the
    /// bars, not by faith. A latched capture wears a lock badge: the next
    /// tap (or the same key) stops it.
    public struct MicButton: View {
        @ObservedObject var talk: PushToTalk
        let spectrum: () -> [Float]
        let voiceActive: () -> Bool
        let hint: String?
        let size: CGFloat

        public init(
            talk: PushToTalk,
            spectrum: @escaping () -> [Float],
            voiceActive: @escaping () -> Bool = { false },
            hint: String? = nil,
            size: CGFloat = 26
        ) {
            self.talk = talk
            self.spectrum = spectrum
            self.voiceActive = voiceActive
            self.hint = hint
            self.size = size
        }

        @State private var pressing = false
        @GestureState private var pressed = false

        public var body: some View {
            HStack(spacing: .inkTight) {
                circle
                if talk.engaged {
                    spectrumCapsule
                        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
                }
                if let hint, !talk.engaged {
                    Text(verbatim: hint)
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: .inkChip))
                }
            }
            .animation(.inkSettle, value: talk.engaged)
        }

        private var circle: some View {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(talk.engaged ? Color.red : .inkRest)
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: talk.engaged ? "mic.fill" : "mic")
                            .font(.system(size: size * 0.45, weight: .medium))
                            .foregroundStyle(talk.engaged ? .white : .white.opacity(0.7))
                    }
                    .scaleEffect(pressed ? 0.9 : 1)
                    .animation(.inkFlick, value: pressed)
                if talk.latched {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(Color.red, in: Circle())
                        .offset(x: 3, y: -3)
                        .transition(.scale)
                }
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = true }
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        talk.pressBegan()
                    }
                    .onEnded { _ in
                        pressing = false
                        talk.pressEnded()
                    }
            )
            .help(
                talk.engaged
                    ? (talk.latched ? "Recording (locked) - tap to stop" : "Recording while held")
                    : "Hold to talk; tap to lock on")
        }

        /// The live spectrum: one red identity, alpha the only variable
        /// (bright = voice detected, dim = room tone), bars centered like a
        /// waveform. Data-driven animation only - it moves because the
        /// AUDIO moves, and rests flat the instant capture stops.
        private var spectrumCapsule: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !talk.engaged)) { _ in
                let bands = spectrum()
                let hot = voiceActive()
                Canvas { context, canvasSize in
                    let count = max(bands.count, 1)
                    let barWidth: CGFloat = 2.5
                    let gap =
                        (canvasSize.width - CGFloat(count) * barWidth) / CGFloat(count + 1)
                    for (index, magnitude) in bands.enumerated() {
                        let height = max(2, CGFloat(magnitude) * (canvasSize.height - 4))
                        let rect = CGRect(
                            x: gap + CGFloat(index) * (barWidth + gap),
                            y: (canvasSize.height - height) / 2,
                            width: barWidth,
                            height: height)
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: barWidth / 2),
                            with: .color(.red.opacity(hot ? 0.95 : 0.35)))
                    }
                }
            }
            .frame(width: 74, height: size)
            .background(.inkRest, in: Capsule())
        }
    }
#endif
