import SwiftUI

/// Text cut in the middle, never at the end: `.truncationMode(.tail)` loses the
/// end, and the end is what tells values apart (`server-1` and `server-2` both read
/// `server…`; a wallet address keeps its prefix and loses the part people check).
/// `.truncationMode(.middle)` cuts at the exact centre, so how much of the end
/// survives depends on the width.
///
/// `tail` says what stays whole: a count of characters (`tail: 6` for a hash), or a
/// separator, everything from its last occurrence (`tail: "/"` keeps a path's file,
/// `"."` an extension). A separator the text does not hold guarantees no tail: the
/// text cuts at its end. The tail is a promise: wider than the room, it overflows.
///
/// When the whole text fits it is drawn as one `Text`, no seam; only a cut text
/// carries the whole as its help tooltip. Same rule as ui's `middle-truncate`.
public struct MiddleTruncate: View {
    public enum Tail: ExpressibleByIntegerLiteral, ExpressibleByStringLiteral, Sendable {
        case count(Int)
        case from(String)

        public init(integerLiteral value: Int) {
            precondition(value >= 0, "MiddleTruncate: a tail of \(value) characters")
            self = .count(value)
        }
        public init(stringLiteral value: String) {
            precondition(!value.isEmpty, "MiddleTruncate: an empty separator")
            self = .from(value)
        }
    }

    let text: String
    let tail: Tail

    public init(_ text: String, tail: Tail = 4) {
        self.text = text
        self.tail = tail
    }

    /// Where `text` splits: the head shrinks, the tail is kept whole.
    public static func split(_ text: String, tail: Tail) -> (head: String, tail: String) {
        let at: String.Index =
            switch tail {
            case .count(let n):
                text.index(text.endIndex, offsetBy: -n, limitedBy: text.startIndex)
                    ?? text.startIndex
            case .from(let separator):
                text.range(of: separator, options: .backwards)?.lowerBound ?? text.endIndex
            }
        return (String(text[..<at]), String(text[at...]))
    }

    public var body: some View {
        let (head, end) = Self.split(text, tail: tail)
        ViewThatFits(in: .horizontal) {
            Text(verbatim: text).lineLimit(1).fixedSize()
            HStack(spacing: 0) {
                Text(verbatim: head).lineLimit(1).truncationMode(.tail)
                Text(verbatim: end).lineLimit(1).fixedSize()
            }
            .help(text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
