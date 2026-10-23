import Foundation

extension Git {
    /// What changed INSIDE a changed line: a removed line and the added line that
    /// replaced it, compared word by word (a longest common subsequence over tokens: a
    /// word, a run of spaces, one punctuation mark), so a renamed variable lights up and
    /// the rest of the line stays quiet.
    public enum Intraline {
        /// Changed stretches of each line, in `Character` offsets, merged across the spaces
        /// between them. Nil when the two lines share too little for the words to mean
        /// anything (under `similarity` of their characters): the whole line changed.
        public static func ranges(old: String, new: String, similarity: Double = 0.4)
            -> (old: [Range<Int>], new: [Range<Int>])?
        {
            let a = tokens(old)
            let b = tokens(new)
            var prefix = 0
            while prefix < a.count, prefix < b.count, a[prefix].text == b[prefix].text {
                prefix += 1
            }
            var suffix = 0
            while suffix < a.count - prefix, suffix < b.count - prefix,
                a[a.count - 1 - suffix].text == b[b.count - 1 - suffix].text
            {
                suffix += 1
            }
            let midA = Array(a[prefix..<(a.count - suffix)])
            let midB = Array(b[prefix..<(b.count - suffix)])
            var keptA = Set<Int>()
            var keptB = Set<Int>()
            // A line of hundreds of tokens is compared only at its ends: the table would
            // cost more than the highlight is worth.
            if midA.count * midB.count <= 40_000 {
                (keptA, keptB) = common(midA.map(\.text), midB.map(\.text))
            }
            let unchanged =
                a.prefix(prefix).reduce(0) { $0 + $1.length }
                + a.suffix(suffix).reduce(0) { $0 + $1.length }
                + keptA.reduce(0) { $0 + midA[$1].length }
            let longest = max(old.count, new.count)
            guard longest > 0, Double(unchanged) / Double(longest) >= similarity else { return nil }
            return (spans(midA, kept: keptA), spans(midB, kept: keptB))
        }

        /// Every changed line of a hunk that has a partner, keyed by its index in
        /// `hunk.lines`: a run of removed lines followed by a run of added ones pair up in
        /// order, as an edit replaces lines one for one.
        public static func pairs(in hunk: Hunk, similarity: Double = 0.4) -> [Int: [Range<Int>]] {
            var out: [Int: [Range<Int>]] = [:]
            let lines = hunk.lines
            var index = 0
            while index < lines.count {
                guard lines[index].kind == .removed else {
                    index += 1
                    continue
                }
                let removedStart = index
                while index < lines.count, lines[index].kind == .removed { index += 1 }
                let addedStart = index
                while index < lines.count, lines[index].kind == .added { index += 1 }
                let count = min(addedStart - removedStart, index - addedStart)
                for offset in 0..<count {
                    let old = removedStart + offset
                    let new = addedStart + offset
                    guard lines[old].text.count <= 2_000, lines[new].text.count <= 2_000,
                        let found = ranges(
                            old: lines[old].text, new: lines[new].text, similarity: similarity)
                    else { continue }
                    out[old] = found.old
                    out[new] = found.new
                }
            }
            return out
        }

        struct Token {
            var text: Substring
            var start: Int
            var length: Int
            var isSpace: Bool
        }

        static func tokens(_ line: String) -> [Token] {
            var out: [Token] = []
            var offset = 0
            var index = line.startIndex
            func kind(_ c: Character) -> Int {
                if c.isLetter || c.isNumber || c == "_" { return 0 }
                if c.isWhitespace { return 1 }
                return 2
            }
            while index < line.endIndex {
                let first = kind(line[index])
                var end = line.index(after: index)
                var length = 1
                if first != 2 {
                    while end < line.endIndex, kind(line[end]) == first {
                        end = line.index(after: end)
                        length += 1
                    }
                }
                out.append(
                    Token(
                        text: line[index..<end], start: offset, length: length, isSpace: first == 1)
                )
                offset += length
                index = end
            }
            return out
        }

        /// The indices of each side that belong to a longest common subsequence.
        static func common(_ a: [Substring], _ b: [Substring]) -> (Set<Int>, Set<Int>) {
            guard !a.isEmpty, !b.isEmpty else { return ([], []) }
            let width = b.count + 1
            var table = [Int](repeating: 0, count: (a.count + 1) * width)
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    table[i * width + j] =
                        a[i] == b[j]
                        ? table[(i + 1) * width + j + 1] + 1
                        : max(table[(i + 1) * width + j], table[i * width + j + 1])
                }
            }
            var keptA = Set<Int>()
            var keptB = Set<Int>()
            var i = 0
            var j = 0
            while i < a.count, j < b.count {
                if a[i] == b[j] {
                    keptA.insert(i)
                    keptB.insert(j)
                    i += 1
                    j += 1
                } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
                    i += 1
                } else {
                    j += 1
                }
            }
            return (keptA, keptB)
        }

        /// The changed tokens as character ranges, joined across the spaces between them
        /// and never starting or ending on a space.
        static func spans(_ tokens: [Token], kept: Set<Int>) -> [Range<Int>] {
            var out: [Range<Int>] = []
            var pendingSpace: Range<Int>?
            for (index, token) in tokens.enumerated() {
                let range = token.start..<(token.start + token.length)
                if token.isSpace {
                    if let last = out.last, last.upperBound == range.lowerBound {
                        pendingSpace = range
                    }
                    continue
                }
                if kept.contains(index) {
                    pendingSpace = nil
                    continue
                }
                if let last = out.last, last.upperBound == range.lowerBound {
                    out[out.count - 1] = last.lowerBound..<range.upperBound
                } else if let space = pendingSpace, let last = out.last,
                    space.upperBound == range.lowerBound
                {
                    out[out.count - 1] = last.lowerBound..<range.upperBound
                } else {
                    out.append(range)
                }
                pendingSpace = nil
            }
            return out
        }
    }
}
