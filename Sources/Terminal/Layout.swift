/// Static terminal layout: aligned tables, key/value blocks, indentation,
/// trees. Cells may be pre-colored: alignment uses visible width, so colored
/// columns line up, and with the palette off the output is plain aligned
/// text for a pipe or a log. Same names and behaviour as ts-utils `cli`.

/// Rows as aligned columns. `head` is bolded; `align` is per column ("l" or
/// "r", default left); the last left-aligned column is not padded, so no
/// line ends in whitespace.
public func table(
    _ rows: [[String]], head: [String]? = nil, align: [Character] = [], gap: Int = 2,
    indent: Int = 0
) -> String {
    let body = (head.map { [$0] } ?? []) + rows
    let columns = body.map(\.count).max() ?? 0
    let widths = (0..<columns).map { c in body.map { c < $0.count ? width($0[c]) : 0 }.max() ?? 0 }
    let separator = String(repeating: " ", count: gap)
    let lead = String(repeating: " ", count: indent)
    func line(_ row: [String]) -> String {
        let cells = (0..<columns).map { c -> String in
            let cell = c < row.count ? row[c] : ""
            if c < align.count, align[c] == "r" { return padStart(cell, widths[c]) }
            return c == columns - 1 ? cell : padEnd(cell, widths[c])
        }
        return trimmedEnd(lead + cells.joined(separator: separator))
    }
    var out: [String] = []
    if let head { out.append(line(head.map(ui.head))) }
    out += rows.map(line)
    return out.joined(separator: "\n")
}

/// A key/value block with aligned, muted keys: a detail view.
public func kv(_ pairs: [(String, String)], indent: Int = 0, gap: Int = 2) -> String {
    let w = pairs.map { width($0.0) }.max() ?? 0
    let lead = String(repeating: " ", count: indent)
    let separator = String(repeating: " ", count: gap)
    return pairs.map { lead + ui.muted(padEnd($0.0, w)) + separator + $0.1 }.joined(separator: "\n")
}

/// Every line of a (possibly multi-line) string indented by `n` spaces.
public func indent(_ s: String, _ n: Int) -> String {
    let lead = String(repeating: " ", count: n)
    return s.split(separator: "\n", omittingEmptySubsequences: false).map { lead + $0 }.joined(
        separator: "\n")
}

/// A labeled node with its child lines drawn under it.
public func tree(_ label: String, _ children: [String], indent: Int = 0) -> String {
    let lead = String(repeating: " ", count: indent)
    return ([lead + label] + children.map { lead + "  " + $0 }).joined(separator: "\n")
}

private func trimmedEnd(_ s: String) -> String {
    var s = Substring(s)
    while s.last?.isWhitespace == true { s.removeLast() }
    return String(s)
}
