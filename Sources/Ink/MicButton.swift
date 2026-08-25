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
// (github.com/adriangalilea/swift-senses). This file owns the FEEL; listen owns
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
    /// The listening identity: Siri-family stops (blue -> violet -> pink),
    /// deliberately NOT red - red is the error/danger register, and a live
    /// microphone is a state, not a problem. The ONE definition: the view
    /// gradient, the Canvas shading, and the latch badge all derive from
    /// this array; alpha and amplitude are the only variables.
    public let micListeningColors: [Color] = [
        Color(red: 0.24, green: 0.65, blue: 1.0),
        Color(red: 0.56, green: 0.39, blue: 1.0),
        Color(red: 1.0, green: 0.36, blue: 0.66),
    ]

    public let micListeningGradient = LinearGradient(
        colors: micListeningColors, startPoint: .leading, endPoint: .trailing)

    /// The button. Idle: a quiet circle with the mic glyph and its keycap
    /// hint. Engaged: the circle fills with the listening gradient and a
    /// waveform capsule unfolds beside it - a smooth mirrored ribbon drawn
    /// from live band magnitudes with a soft glow, full-amplitude and
    /// saturated while voice is detected, low and dim over room tone, so
    /// "is it hearing ME" is answered by the wave, not by faith. A latched
    /// capture wears a lock badge: the next tap (or the same key) stops it.
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
                    .fill(.inkRest)
                    .overlay {
                        if talk.engaged {
                            Circle().fill(micListeningGradient)
                        }
                    }
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
                        .background(micListeningColors[1], in: Circle())
                        .offset(x: 3, y: -3)
                        .transition(.scale)
                }
            }
            .contentShape(Circle())
            // Press state is @GestureState ALONE: it resets on gesture end
            // AND on cancellation (view removed mid-press, another gesture
            // claiming the touch), where .onEnded never fires - so every
            // way a press can die reaches pressEnded and the mic cannot
            // stay hot behind a vanished button.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = true }
            )
            .onChange(of: pressed) { _, down in
                down ? talk.pressBegan() : talk.pressEnded()
            }
            .onDisappear { talk.stop() }
            .help(
                talk.engaged
                    ? (talk.latched ? "Recording (locked) - tap to stop" : "Recording while held")
                    : "Hold to talk; tap to lock on")
        }

        /// The live waveform: a smooth mirrored ribbon through the band
        /// magnitudes, gradient-filled with a soft glow beneath and a crisp
        /// core line - full amplitude and opacity while voice is detected,
        /// low and dim over room tone. Data-driven animation only: it moves
        /// because the AUDIO moves, and rests flat the instant capture
        /// stops.
        private var spectrumCapsule: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !talk.engaged)) { _ in
                let bands = spectrum()
                let hot = voiceActive()
                Canvas { context, canvasSize in
                    let inset = CGRect(origin: .zero, size: canvasSize)
                        .insetBy(dx: 5, dy: 2)
                    let gain: CGFloat = hot ? 1.0 : 0.4
                    let ribbon = Self.wavePath(bands: bands, in: inset, gain: gain)
                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: micListeningColors),
                        startPoint: CGPoint(x: inset.minX, y: 0),
                        endPoint: CGPoint(x: inset.maxX, y: 0))
                    // Glow under, ribbon over, core line on top: the Siri
                    // depth recipe, all one gradient.
                    context.drawLayer { glow in
                        glow.addFilter(.blur(radius: 3))
                        glow.opacity = hot ? 0.7 : 0.3
                        glow.fill(ribbon, with: shading)
                    }
                    context.opacity = hot ? 0.95 : 0.45
                    context.fill(ribbon, with: shading)
                    let core = Self.wavePath(bands: bands, in: inset, gain: gain * 0.55)
                    context.opacity = hot ? 0.9 : 0.5
                    context.fill(core, with: .color(.white.opacity(0.55)))
                }
            }
            .frame(width: 74, height: size)
            .background(.inkRest, in: Capsule())
        }

        /// A closed, vertically mirrored ribbon through the magnitudes:
        /// Catmull-Rom smoothed so speech reads as a wave, never as bars.
        /// Silence collapses to a hairline center - the resting state IS
        /// the visualization of "nothing to hear".
        private static func wavePath(bands: [Float], in rect: CGRect, gain: CGFloat) -> Path {
            let midY = rect.midY
            let halfHeight = rect.height / 2
            let count = max(bands.count, 2)
            let points: [CGPoint] = (0..<count).map { index in
                let magnitude = index < bands.count ? CGFloat(bands[index]) : 0
                return CGPoint(
                    x: rect.minX + rect.width * CGFloat(index) / CGFloat(count - 1),
                    y: max(1.2, magnitude * halfHeight * gain))
            }
            func smooth(_ pts: [CGPoint], into path: inout Path, flip: CGFloat) {
                let mapped = pts.map { CGPoint(x: $0.x, y: midY + flip * $0.y) }
                guard let first = mapped.first else { return }
                if flip > 0 {
                    path.addLine(to: first)
                } else {
                    path.move(to: first)
                }
                for index in 1..<mapped.count {
                    let previous = mapped[index - 1]
                    let current = mapped[index]
                    let before = mapped[max(0, index - 2)]
                    let after = mapped[min(mapped.count - 1, index + 1)]
                    let control1 = CGPoint(
                        x: previous.x + (current.x - before.x) / 6,
                        y: previous.y + (current.y - before.y) / 6)
                    let control2 = CGPoint(
                        x: current.x - (after.x - previous.x) / 6,
                        y: current.y - (after.y - previous.y) / 6)
                    path.addCurve(to: current, control1: control1, control2: control2)
                }
            }
            var path = Path()
            smooth(points, into: &path, flip: -1)
            smooth(points.reversed(), into: &path, flip: 1)
            path.closeSubpath()
            return path
        }
    }
#endif
