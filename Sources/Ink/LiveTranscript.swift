import SwiftUI

// The machine's hearing made visible while it forms - MicButton's sibling:
// that file owns the mic affordance, this one owns the live-caption
// readout. The words come from a speech session (in the studio, listen's
// volatile + final segments); this file owns the FEEL.
//
// Two registers of truth, the ghost-text grammar:
//   - the PREVIEW is wet ink: italic, slightly dimmed, mutating in place
//     under the recognizer - undecided, never act on it. It updates with
//     NO animation: wet ink must track the voice with zero added latency.
//   - a COMMIT crystallizes: the text snaps solid at full weight, carries
//     its locale + confidence as quiet mono metadata, and then FADES like
//     a caption - the words already live where they were written (the
//     consumer's pane/document), so the readout stays about the present,
//     never an archive.
// Confidence colors NOTHING unless it means something: below 0.7 the
// metadata pill alone warms to orange (one hue, carrying meaning).
// Layout-neutral and content-hugging - the host brings the chrome
// (`hudGlass()` floating, or a list row in a historical view).

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

    @Published public private(set) var committed: [Committed] = []
    @Published public private(set) var preview = ""
    @Published public private(set) var previewLocale: String?
    /// The language on the air right now (last preview/commit that named
    /// one) - the capsule's FIXED flag slot reads this, so the flag never
    /// travels with the text.
    @Published public private(set) var currentLocale: String?

    /// How long a committed line stays before fading - caption timing.
    public var linger: TimeInterval = 2.4
    /// How long wet ink survives without an update before it EVAPORATES:
    /// a preview the recognizer abandoned (or that lost the race) was
    /// never real, and stale wet ink lingering forever reads as the
    /// machine being stuck.
    public var previewLinger: TimeInterval = 2.0

    private var previewGeneration = 0

    public init() {}

    public func preview(_ text: String, locale: String? = nil) {
        preview = text
        previewLocale = locale
        if let locale { currentLocale = locale }
        previewGeneration += 1
        let generation = previewGeneration
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(previewLinger))
            guard previewGeneration == generation, !self.preview.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                self.preview = ""
                self.previewLocale = nil
            }
        }
    }

    /// The preview crystallized (or a final arrived unheralded). Clears
    /// the wet ink it supersedes and schedules the caption fade.
    public func commit(_ text: String, locale: String? = nil, confidence: Double? = nil) {
        let line = Committed(text: text, locale: locale, confidence: confidence)
        committed.append(line)
        preview = ""
        previewLocale = nil
        if let locale { currentLocale = locale }
        previewGeneration += 1
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
        preview = ""
        previewLocale = nil
        currentLocale = nil
        previewGeneration += 1
    }
}

/// One transcript line - the grammar SHARED by live and MATERIALIZED
/// rendering, so a transcript reads identically while it forms and years
/// later in a historical view (a consumer persists text + locale +
/// confidence per segment and renders these): solid text for committed
/// words, `wet: true` for the in-progress register, and the quiet mono
/// metadata pill - language prefix ("es", never "es-ES") with the
/// confidence score, warming to orange below 0.7 (the ONE place that hue
/// lives). Layout-neutral: no greedy frames - the host decides whether
/// rows hug (a floating capsule) or fill (a document view).
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
        // Flag, never a code - codes are engineering leaking into the
        // interface. Confidence stays a number; sub-0.7 warms it.
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
        // The flag lives in a FIXED trailing slot - reserved even when
        // empty, so it never travels with the text (autodetect today; the
        // slot is where the language toggle/dropdown lands later).
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                if model.committed.isEmpty && model.preview.isEmpty {
                    Text(hint)
                        .font(.system(size: 16))
                        .italic()
                        .foregroundStyle(.primary.opacity(0.5))
                }
                ForEach(model.committed) { line in
                    TranscriptLine(text: line.text, confidence: line.confidence)
                        .transition(.opacity)
                }
                if !model.preview.isEmpty {
                    TranscriptLine(text: model.preview, wet: true)
                        .transition(.opacity)
                }
            }
            Text(LocaleFlag.emoji(model.currentLocale) ?? " ")
                .font(.system(size: 13))
                .frame(width: 20, alignment: .trailing)
                .opacity(0.9)
        }
    }
}
