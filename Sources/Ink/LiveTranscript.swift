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
                row(
                    text: Text(line.text).font(.callout),
                    locale: line.locale, confidence: line.confidence
                )
                .transition(.opacity)
            }
            if !model.preview.isEmpty {
                row(
                    text: Text(model.preview).font(.callout.italic())
                        .foregroundStyle(.secondary),
                    locale: model.previewLocale, confidence: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private func row(text: Text, locale: String?, confidence: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            text.frame(maxWidth: .infinity, alignment: .leading)
            if locale != nil || confidence != nil {
                pill(locale: locale, confidence: confidence)
            }
        }
    }

    private func pill(locale: String?, confidence: Double?) -> some View {
        // Metadata voice: mono, lowercase, tiny. The language prefix alone
        // ("es", never "es-ES") - the arbitration verdict at a glance; a
        // sub-0.7 confidence warms the pill, the ONE place that hue lives.
        let lang = locale.map { String($0.prefix(2)).lowercased() }
        let score = confidence.map { String(format: "%.2f", $0) }
        let label = [lang, score].compactMap { $0 }.joined(separator: " ")
        let weak = (confidence ?? 1) < 0.7
        return Text(label)
            .font(.caption2.monospaced())
            .foregroundStyle(weak ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
    }
}
