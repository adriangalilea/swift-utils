import SwiftUI

// The machine's hearing made visible while it forms - MicButton's sibling:
// that file owns the mic affordance, this one owns the live-caption
// readout. The words come from a speech session (in the studio, listen's
// volatile + final segments); this file owns the FEEL.
//
// Two registers of truth, the ghost-text grammar:
//   - the PREVIEW is wet ink: italic, dim, mutating in place under the
//     recognizer - undecided, never act on it.
//   - a COMMIT crystallizes: the text snaps solid at full weight, carries
//     its locale + confidence as quiet mono metadata, and then FADES like
//     a caption - the words already live where they were written (the
//     consumer's pane/document), so the readout stays about the present,
//     never an archive.
// Confidence colors NOTHING unless it means something: below 0.7 the
// metadata pill alone warms to orange (one hue, carrying meaning).
// Embeddable anywhere; the host brings the chrome (panel, capsule,
// sidebar).

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

    /// How long a committed line stays before fading - caption timing.
    public var linger: TimeInterval = 2.4

    public init() {}

    public func preview(_ text: String, locale: String? = nil) {
        preview = text
        previewLocale = locale
    }

    /// The preview crystallized (or a final arrived unheralded). Clears
    /// the wet ink it supersedes and schedules the caption fade.
    public func commit(_ text: String, locale: String? = nil, confidence: Double? = nil) {
        let line = Committed(text: text, locale: locale, confidence: confidence)
        withAnimation(.easeOut(duration: 0.15)) {
            committed.append(line)
            preview = ""
            previewLocale = nil
        }
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(linger))
            withAnimation(.easeOut(duration: 0.6)) {
                self.committed.removeAll { $0.id == line.id }
            }
        }
    }

    public func reset() {
        committed = []
        preview = ""
        previewLocale = nil
    }
}

/// One transcript line - the grammar SHARED by live and MATERIALIZED
/// rendering, so a transcript reads identically while it forms and years
/// later in a historical view (a consumer persists text + locale +
/// confidence per segment and renders these): solid text for committed
/// words, `wet: true` for the in-progress register (italic, dim), and the
/// quiet mono metadata pill - language prefix ("es", never "es-ES") with
/// the confidence score, warming to orange below 0.7 (the ONE place that
/// hue lives).
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if wet {
                    Text(text).font(.callout.italic()).foregroundStyle(.secondary)
                } else {
                    Text(text).font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if locale != nil || confidence != nil {
                pill
            }
        }
    }

    private var pill: some View {
        let lang = locale.map { String($0.prefix(2)).lowercased() }
        let score = confidence.map { String(format: "%.2f", $0) }
        let label = [lang, score].compactMap { $0 }.joined(separator: " ")
        let weak = (confidence ?? 1) < 0.7
        return Text(label)
            .font(.caption2.monospaced())
            .foregroundStyle(weak ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
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
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            if model.committed.isEmpty && model.preview.isEmpty {
                Text(hint)
                    .font(.callout.italic())
                    .foregroundStyle(.tertiary)
            }
            ForEach(model.committed) { line in
                TranscriptLine(
                    text: line.text, locale: line.locale, confidence: line.confidence
                )
                .transition(.opacity)
            }
            if !model.preview.isEmpty {
                TranscriptLine(text: model.preview, locale: model.previewLocale, wet: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}
