import SwiftUI

// The ask layer's face - LiveTranscript's sibling in the HUD family, same
// laws: content-hugging, host brings the chrome (`hudGlass()` floating or
// embedded inline), quiet mono metadata, hue only when it carries meaning.
//
// The grammar: the QUESTION is the subject, solid. The channels row is
// the affordance - which senses are listening RIGHT NOW ("voice · nod",
// mono, only the reachable ones; a channel that cannot hear you is not
// listed, never dimmed decoration). The VERDICT crystallizes in place of
// the channels - the answer word solid semibold with the winning channel
// + confidence as its pill - and unanswered exits (timeout, cancelled)
// stay in the wet register: nothing was decided.

@MainActor
public final class AskPromptModel: ObservableObject {
    public struct Verdict: Equatable {
        public let word: String
        public let decided: Bool
        public let source: String?
        public let confidence: Double?

        public init(word: String, decided: Bool, source: String?, confidence: Double?) {
            self.word = word
            self.decided = decided
            self.source = source
            self.confidence = confidence
        }
    }

    @Published public private(set) var question = ""
    @Published public private(set) var channels: [String] = []
    @Published public private(set) var verdict: Verdict?

    public init() {}

    public func ask(_ question: String, channels: [String]) {
        self.question = question
        self.channels = channels
        verdict = nil
    }

    /// The ask resolved. `decided` separates a real answer (crystallizes)
    /// from an unanswered exit (stays wet).
    public func resolve(
        _ word: String, decided: Bool, source: String? = nil, confidence: Double? = nil
    ) {
        withAnimation(.easeOut(duration: 0.15)) {
            verdict = Verdict(word: word, decided: decided, source: source, confidence: confidence)
        }
    }

    public func reset() {
        question = ""
        channels = []
        verdict = nil
    }
}

public struct AskPrompt: View {
    @ObservedObject private var model: AskPromptModel

    public init(model: AskPromptModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.question)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
            if let verdict = model.verdict {
                verdictRow(verdict)
            } else {
                Text(model.channels.joined(separator: " · "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary.opacity(0.45))
            }
        }
    }

    private func verdictRow(_ verdict: AskPromptModel.Verdict) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if verdict.decided {
                Text(verdict.word)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            } else {
                Text(verdict.word)
                    .font(.system(size: 16))
                    .italic()
                    .foregroundStyle(.primary.opacity(0.5))
            }
            if verdict.source != nil || verdict.confidence != nil {
                pill(source: verdict.source, confidence: verdict.confidence)
            }
        }
    }

    private func pill(source: String?, confidence: Double?) -> some View {
        let score = confidence.map { String(format: "%.2f", $0) }
        let label = [source, score].compactMap { $0 }.joined(separator: " ")
        let weak = (confidence ?? 1) < 0.7
        return Text(label)
            .font(.caption.monospaced())
            .foregroundStyle(
                weak ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary.opacity(0.45)))
    }
}
