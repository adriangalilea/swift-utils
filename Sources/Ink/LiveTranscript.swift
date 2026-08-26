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
//     EVAPORATES with a fade - abandoned ink was never real.
//   - a COMMIT crystallizes: solid, full weight, confidence as quiet mono
//     metadata (sub-0.7 warms to orange - the one hue, carrying meaning).
//     A committed line then holds an EDIT WINDOW before it expires - and
//     expiry is the moment the consumer writes it where it belongs
//     (`onExpire`). Confident lines leave fast; doubtful lines LINGER, so
//     the human can step in: click to edit in place, or pick from the
//     recognizer's alternatives on the pill. A correction seals the line
//     immediately and reports through `onCorrection` - the consumer's
//     RLHF seam (original vs corrected, ledgered).
//   - HOVER PAUSES the clock (`paused`): nothing expires or evaporates
//     while the pointer is over the readout, so there is always time to
//     click.
//   - THE RACE: before any final, every candidate recognizer's preview
//     shows, divided, each tagged with its flag. A final CROWNS a winner:
//     losers vanish and are ignored from then on.
//   - the FLAG SLOT is leading and RESERVED - it never travels with the
//     text. Undecided shows the neutral glyph; the crowned flag lands with
//     the first commit. Given a `LanguagePicker`, the slot IS the language
//     control: Auto or a forced language for when the flip-flopping is
//     tiresome and the human knows what they are speaking.

/// The state machine + the clocks. Feed it `preview`/`commit` from a
/// speech session; the view renders whatever it holds; `onExpire` is when
/// a line becomes the consumer's.
@MainActor
public final class LiveTranscriptModel: ObservableObject {
    public struct Committed: Identifiable, Equatable {
        public let id = UUID()
        public var text: String
        public let original: String
        public let locale: String?
        public let confidence: Double?
        public let alternatives: [String]
        public var expiresAt: Date
        public var edited: Bool { text != original }
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
    /// The crowned language - set ONLY by a commit. nil = undecided.
    @Published public private(set) var winner: String?
    /// Hover: the clocks stop while true.
    @Published public var paused = false
    @Published public private(set) var editing: UUID?
    /// The in-place editor's text while `editing` is set.
    @Published public var draft = ""

    /// Edit windows by confidence: a confident line leaves fast, a
    /// doubtful one lingers for the human.
    public var lingerConfident: TimeInterval = 1.2
    public var lingerDoubtful: TimeInterval = 3.5
    public var doubtBelow: Double = 0.8
    /// How long wet ink survives without an update before evaporating.
    public var previewLinger: TimeInterval = 2.0

    /// A line's window closed, or the human sealed it: write it where it
    /// belongs NOW.
    public var onExpire: ((Committed) -> Void)?
    /// The human corrected a line (in place, or an alternative) - the RLHF
    /// seam: the consumer ledgers `original` vs `text`.
    public var onCorrection: ((Committed) -> Void)?
    /// Nothing on screen and no race live - a host may hide its chrome.
    public var onIdle: (() -> Void)?

    private var ticker: Task<Void, Never>?

    public init() {}

    // MARK: - Feeding

    public func preview(_ text: String, locale: String? = nil) {
        if let winner, let locale, locale != winner { return }
        let race = Race(locale: locale, text: text, at: Date())
        if let index = races.firstIndex(where: { $0.id == race.id }) {
            races[index] = race
        } else {
            races.append(race)
            races.sort { $0.id < $1.id }
        }
        armTicker()
    }

    public func commit(
        _ text: String, locale: String? = nil, confidence: Double? = nil,
        alternatives: [String] = []
    ) {
        let doubtful = (confidence ?? 0) < doubtBelow
        let line = Committed(
            text: text, original: text, locale: locale, confidence: confidence,
            alternatives: alternatives.filter { $0 != text },
            expiresAt: Date().addingTimeInterval(doubtful ? lingerDoubtful : lingerConfident))
        committed.append(line)
        races = []
        if let locale { winner = locale }
        armTicker()
    }

    // MARK: - The human steps in

    public func beginEdit(_ id: UUID) {
        guard let line = committed.first(where: { $0.id == id }) else { return }
        editing = id
        draft = line.text
    }

    /// Seal the edit: the line becomes the consumer's immediately.
    public func endEdit() {
        guard let id = editing, let index = committed.firstIndex(where: { $0.id == id }) else {
            editing = nil
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = nil
        guard !text.isEmpty else { return }
        committed[index].text = text
        seal(index)
    }

    public func cancelEdit() {
        editing = nil
    }

    public func choose(_ alternative: String, for id: UUID) {
        guard let index = committed.firstIndex(where: { $0.id == id }) else { return }
        committed[index].text = alternative
        seal(index)
    }

    /// Everything pending becomes the consumer's now (a session ending).
    public func flushAll() {
        editing = nil
        for line in committed { onExpire?(line) }
        committed = []
        races = []
    }

    public func reset() {
        committed = []
        races = []
        winner = nil
        editing = nil
        paused = false
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Clocks

    private func seal(_ index: Int) {
        let line = committed[index]
        if line.edited { onCorrection?(line) }
        onExpire?(line)
        withAnimation(.easeOut(duration: 0.35)) {
            committed.remove(at: index)
        }
        if committed.isEmpty && races.isEmpty { onIdle?() }
    }

    private func armTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.2))
                guard let self else { return }
                if !paused {
                    let now = Date()
                    let due = committed.filter { $0.expiresAt <= now && $0.id != editing }
                    for line in due { onExpire?(line) }
                    let staleCutoff = now.addingTimeInterval(-previewLinger)
                    if !due.isEmpty || races.contains(where: { $0.at < staleCutoff }) {
                        withAnimation(.easeOut(duration: 0.45)) {
                            self.committed.removeAll { line in due.contains { $0.id == line.id } }
                            self.races.removeAll { $0.at < staleCutoff }
                        }
                    }
                }
                if committed.isEmpty && races.isEmpty {
                    ticker = nil
                    onIdle?()
                    return
                }
            }
        }
    }
}

/// The language control in the flag slot: nil = Auto (the race decides).
public struct LanguagePicker {
    public var options: [String]
    public var selected: String?
    public var onSelect: (String?) -> Void

    public init(options: [String], selected: String?, onSelect: @escaping (String?) -> Void) {
        self.options = options
        self.selected = selected
        self.onSelect = onSelect
    }
}

/// The metadata pill: the locale's FLAG (never a code) and the confidence
/// score, warming to orange below 0.7 - the one place that hue lives.
public struct ConfidencePill: View {
    public var locale: String?
    public var confidence: Double?

    public init(locale: String? = nil, confidence: Double? = nil) {
        self.locale = locale
        self.confidence = confidence
    }

    public var body: some View {
        let flag = LocaleFlag.emoji(locale)
        let score = confidence.map { String(format: "%.2f", $0) }
        let label = [flag, score].compactMap { $0 }.joined(separator: " ")
        let weak = (confidence ?? 1) < 0.7
        Text(label)
            .font(.caption.monospaced())
            .foregroundStyle(
                weak ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary.opacity(0.45)))
    }
}

/// One transcript line - the grammar SHARED by live and MATERIALIZED
/// rendering, so a transcript reads identically while it forms and years
/// later in a historical view (a consumer persists text + locale +
/// confidence per segment and renders these). Layout-neutral: no greedy
/// frames - the host decides whether rows hug or fill.
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
            if locale != nil || confidence != nil {
                ConfidencePill(locale: locale, confidence: confidence)
            }
        }
    }
}

public struct LiveTranscript: View {
    @ObservedObject private var model: LiveTranscriptModel
    private let hint: String
    private let languages: LanguagePicker?
    @FocusState private var editorFocused: Bool

    public init(
        model: LiveTranscriptModel, hint: String = "listening", languages: LanguagePicker? = nil
    ) {
        self.model = model
        self.hint = hint
        self.languages = languages
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
                    committedRow(line).transition(.opacity)
                }
                if model.races.count > 1 {
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

    @ViewBuilder
    private func committedRow(_ line: LiveTranscriptModel.Committed) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if model.editing == line.id {
                TextField("", text: $model.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($editorFocused)
                    .onSubmit { model.endEdit() }
                    .onExitCommand { model.cancelEdit() }
                    .onAppear { editorFocused = true }
            } else {
                Text(line.text)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                    .onTapGesture { model.beginEdit(line.id) }
            }
            if line.alternatives.isEmpty {
                ConfidencePill(confidence: line.confidence)
            } else {
                // The recognizer's own second guesses, one click away.
                Menu {
                    ForEach(line.alternatives, id: \.self) { alternative in
                        Button(alternative) { model.choose(alternative, for: line.id) }
                    }
                } label: {
                    ConfidencePill(confidence: line.confidence)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    /// The LEADING flag slot, always reserved. With a picker it is the
    /// language control; without, a readout.
    @ViewBuilder
    private var slot: some View {
        let shown = languages?.selected ?? model.winner
        if let languages {
            Menu {
                Button {
                    languages.onSelect(nil)
                } label: {
                    Label("Auto", systemImage: "globe")
                }
                Divider()
                ForEach(languages.options, id: \.self) { option in
                    Button {
                        languages.onSelect(option)
                    } label: {
                        Text(
                            "\(LocaleFlag.emoji(option) ?? "") \(Locale.current.localizedString(forIdentifier: option) ?? option)"
                        )
                    }
                }
            } label: {
                slotGlyph(shown)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        } else {
            slotGlyph(shown)
        }
    }

    private func slotGlyph(_ locale: String?) -> some View {
        Group {
            if let flag = LocaleFlag.emoji(locale) {
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
