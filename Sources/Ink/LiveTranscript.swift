import SwiftUI

// The machine's hearing made visible while it forms - MicButton's sibling:
// that file owns the mic affordance, this one owns the live-caption
// readout. The words come from a speech session (in the studio, listen's
// volatile + final segments); this file owns the FEEL.
//
// The grammar:
//   - wet ink: italic, slightly dimmed, mutating in place - undecided,
//     never act on it. Zero animation on updates (it must track the voice
//     with no added latency); ink with no update inside `previewLinger`
//     EVAPORATES with a fade - abandoned ink was never real, and stale
//     wet ink lingering reads as the machine being stuck.
//   - a COMMIT crystallizes: solid, full weight, confidence as quiet mono
//     metadata (sub-0.7 warms to orange - the one hue, carrying meaning),
//     then FADES like a caption: the words already live where they were
//     written.
//   - THE RACE: before any final, every candidate recognizer's preview
//     shows, divided, each tagged with its flag - you watch the
//     arbitration. A final CROWNS a winner: losers vanish and are ignored
//     from then on; for a given stretch of audio there is one winner.
//   - the FLAG SLOT is leading and RESERVED - it never travels with the
//     text. Undecided shows the neutral glyph; the winner's flag lands
//     with the first commit. (The slot is where the language
//     toggle/dropdown lives later; autodetect today.)

/// The state machine + caption decay. Feed it `preview`/`commit` from a
/// speech session; the view renders whatever it holds.
@MainActor
public final class LiveTranscriptModel: ObservableObject {
    public struct Committed: Identifiable, Equatable {
        public let id = UUID()
        public let text: String
        public let locale: String?
        public let confidence: Double?
    }

    public struct Race: Identifiable, Equatable {
        public var id: String { locale ?? "" }
        public let locale: String?
        public let text: String
        public let at: Date
    }

    @Published public private(set) var committed: [Committed] = []
    /// One live preview per candidate recognizer, stable order.
    @Published public private(set) var races: [Race] = []
    /// The crowned language - set ONLY by a commit. nil = undecided (the
    /// slot shows the neutral glyph, every race shows).
    @Published public private(set) var winner: String?

    /// How long a committed line stays before fading - caption timing.
    public var linger: TimeInterval = 2.4
    /// How long wet ink survives without an update before evaporating.
    public var previewLinger: TimeInterval = 2.0

    private var pruner: Task<Void, Never>?

    public init() {}

    public func preview(_ text: String, locale: String? = nil) {
        // A crowned race silences the losers outright.
        if let winner, let locale, locale != winner { return }
        let race = Race(locale: locale, text: text, at: Date())
        if let index = races.firstIndex(where: { $0.id == race.id }) {
            races[index] = race
        } else {
            races.append(race)
            races.sort { $0.id < $1.id }
        }
        armPruner()
    }

    /// A final crowned its locale. Clears every race and schedules the
    /// caption fade.
    public func commit(_ text: String, locale: String? = nil, confidence: Double? = nil) {
        let line = Committed(text: text, locale: locale, confidence: confidence)
        committed.append(line)
        races = []
        if let locale { winner = locale }
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(linger))
            withAnimation(.easeOut(duration: 0.5)) {
                self.committed.removeAll { $0.id == line.id }
            }
        }
    }

    public func reset() {
        committed = []
        races = []
        winner = nil
        pruner?.cancel()
        pruner = nil
    }

    private func armPruner() {
        guard pruner == nil else { return }
        pruner = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                guard let self else { return }
                let cutoff = Date().addingTimeInterval(-previewLinger)
                if races.contains(where: { $0.at < cutoff }) {
                    withAnimation(.easeOut(duration: 0.45)) {
                        self.races.removeAll { $0.at < cutoff }
                    }
                }
                if races.isEmpty {
                    pruner = nil
                    return
                }
            }
        }
    }
}

/// One transcript line - the grammar SHARED by live and MATERIALIZED
/// rendering, so a transcript reads identically while it forms and years
/// later in a historical view (a consumer persists text + locale +
/// confidence per segment and renders these): solid text for committed
/// words, `wet: true` for the in-progress register, and the quiet mono
/// metadata pill - the locale's FLAG (never a code) with the confidence
/// score, warming to orange below 0.7. Layout-neutral: no greedy frames -
/// the host decides whether rows hug or fill.
public struct TranscriptLine: View {
    public var text: String
    public var locale: String?
    public var confidence: Double?
    public var wet: Bool

    public init(
        text: String, locale: String? = nil, confidence: Double? = nil, wet: Bool = false
    ) {
        self.text = text
        self.locale = locale
        self.confidence = confidence
        self.wet = wet
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if wet {
                    Text(text)
                        .font(.system(size: 16))
                        .italic()
                        .foregroundStyle(.primary.opacity(0.72))
                } else {
                    Text(text)
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                }
            }
            if locale != nil || confidence != nil {
                pill
            }
        }
    }

    private var pill: some View {
        let flag = LocaleFlag.emoji(locale)
        let score = confidence.map { String(format: "%.2f", $0) }
        let label = [flag, score].compactMap { $0 }.joined(separator: " ")
        let weak = (confidence ?? 1) < 0.7
        return Text(label)
            .font(.caption.monospaced())
            .foregroundStyle(
                weak ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary.opacity(0.45)))
    }
}

public struct LiveTranscript: View {
    @ObservedObject private var model: LiveTranscriptModel
    private let hint: String

    public init(model: LiveTranscriptModel, hint: String = "listening") {
        self.model = model
        self.hint = hint
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            slot
            VStack(alignment: .leading, spacing: 5) {
                if model.committed.isEmpty && model.races.isEmpty {
                    Text(hint)
                        .font(.system(size: 16))
                        .italic()
                        .foregroundStyle(.primary.opacity(0.5))
                }
                ForEach(model.committed) { line in
                    TranscriptLine(text: line.text, confidence: line.confidence)
                        .transition(.opacity)
                }
                if model.races.count > 1 {
                    // The race, visible: every candidate's guess, divided,
                    // each under its own flag - until a final crowns one.
                    ForEach(Array(model.races.enumerated()), id: \.element.id) { index, race in
                        if index > 0 {
                            Divider().opacity(0.25)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(LocaleFlag.emoji(race.locale) ?? "·")
                                .font(.system(size: 11))
                                .opacity(0.8)
                            TranscriptLine(text: race.text, wet: true)
                        }
                        .transition(.opacity)
                    }
                } else if let race = model.races.first {
                    TranscriptLine(text: race.text, wet: true)
                        .transition(.opacity)
                }
            }
        }
    }

    /// The LEADING flag slot, always reserved - the flag never travels
    /// with the text. Undecided = the neutral glyph.
    private var slot: some View {
        Group {
            if let flag = LocaleFlag.emoji(model.winner) {
                Text(flag).font(.system(size: 14))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.35))
            }
        }
        .frame(width: 20, height: 20)
    }
}
