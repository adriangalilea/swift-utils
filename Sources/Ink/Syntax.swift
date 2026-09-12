import SwiftUI

/// Review-body coloring for approval surfaces: the text a human reads before
/// saying yes, told apart by what the requester SAID it is, never guessed.
/// A diff is red/green by line prefix with `@@` headers muted; a shell
/// command gets its verbs, flags, strings and operators told apart; anything
/// else stays plain. Coloring never rewrites a character: the attributed
/// output's characters are the input, exactly, so what is approved is what
/// was shown.
public enum Syntax {
    /// The wire vocabulary a requester declares ("shell", "diff", "text");
    /// anything unrecognized is plain, never an error.
    public enum Format: String, Sendable {
        case shell
        case diff
        case plain = "text"

        public init(_ raw: String?) {
            self = raw.flatMap(Format.init(rawValue:)) ?? .plain
        }
    }

    public static func highlight(_ text: String, as format: Format) -> AttributedString {
        switch format {
        case .diff: diff(text)
        case .shell: shell(text)
        case .plain: AttributedString(text)
        }
    }

    private static func diff(_ text: String) -> AttributedString {
        var out = AttributedString()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            var run = AttributedString(String(line))
            if line.hasPrefix("+") {
                run.foregroundColor = .green
            } else if line.hasPrefix("-") {
                run.foregroundColor = .red
            } else if line.hasPrefix("@@") {
                run.foregroundColor = .secondary
            }
            out += run
            if index < lines.count - 1 { out += AttributedString("\n") }
        }
        return out
    }

    private static func shell(_ text: String) -> AttributedString {
        var out = AttributedString()
        var word = ""
        var quote: Character?
        var verbNext = true
        func flush() {
            guard !word.isEmpty else { return }
            var run = AttributedString(word)
            if quote != nil {
                run.foregroundColor = .teal
            } else if word.hasPrefix("-") {
                run.foregroundColor = .secondary
            } else if verbNext {
                // Emphasis by intent, not a hardcoded font: the verb stays
                // bold at whatever size the surface renders the block.
                run.inlinePresentationIntent = .stronglyEmphasized
                run.foregroundColor = .accentColor
                verbNext = false
            }
            out += run
            word = ""
        }
        for character in text {
            if let open = quote {
                word.append(character)
                if character == open {
                    flush()
                    quote = nil
                }
                continue
            }
            switch character {
            case "\"", "'":
                flush()
                quote = character
                word.append(character)
            case " ", "\t", "\n":
                flush()
                out += AttributedString(String(character))
                if character == "\n" { verbNext = true }
            case "|", "&", ";", ">", "<":
                flush()
                var run = AttributedString(String(character))
                run.foregroundColor = .orange
                out += run
                verbNext = true
            default:
                word.append(character)
            }
        }
        flush()
        return out
    }
}

/// The block itself: monospaced, selectable, hugging its content. The host
/// brings the chrome (scroll bounds, background, padding) - two surfaces
/// showing the same evidence must color it identically, and this is how.
public struct SyntaxText: View {
    private let text: String
    private let format: Syntax.Format

    public init(_ text: String, format: Syntax.Format) {
        self.text = text
        self.format = format
    }

    public init(_ text: String, format raw: String?) {
        self.init(text, format: Syntax.Format(raw))
    }

    public var body: some View {
        Text(Syntax.highlight(text, as: format))
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
