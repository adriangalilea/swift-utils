extension MarkdownDocument {
    /// Text still arriving, made safe to draw: what was cut mid-construct at its end is
    /// closed or held back, so a reader sees the words and never the syntax they are
    /// waiting on. Only the last block is touched (everything before it is complete by
    /// construction), and only at its end, so every position in what is kept stays the
    /// source's.
    ///
    /// - Inside an open code fence: nothing. CommonMark runs the fence to the end.
    /// - A table whose head has arrived and whose delimiter row has not (one `|` line,
    ///   or a second still being written): held back until it is a table, instead of
    ///   flashing as a paragraph of pipes; so is a row begun with no words in it yet.
    /// - An unclosed `` ` ``, `*`, `**`, `***` or `~~`: closed where its content has
    ///   started, dropped where nothing follows it yet. A link cut in its `](url`: closed.
    static func settled(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        // The last line is still being written unless the text ends with its newline.
        let partial = !text.hasSuffix("\n")
        if !partial { lines.removeLast() }
        // Where the last block starts (after the last blank line), and whether the text
        // ends inside a fence.
        var fence: (mark: Character, count: Int)?
        var blockStart = 0
        for (index, line) in lines.enumerated() {
            let lead = line.prefix(while: { $0 == " " })
            let body = line.dropFirst(lead.count)
            if lead.count < 4, let mark = body.first, mark == "`" || mark == "~" {
                let run = body.prefix(while: { $0 == mark }).count
                if let open = fence {
                    if mark == open.mark, run >= open.count,
                        body.dropFirst(run).allSatisfy(\.isWhitespace)
                    {
                        fence = nil
                        blockStart = index + 1
                    }
                    continue
                }
                if run >= 3 {
                    fence = (mark, run)
                    continue
                }
            }
            if fence == nil, line.allSatisfy(\.isWhitespace) { blockStart = index + 1 }
        }
        if fence != nil || blockStart >= lines.count { return text }

        let kept = lines[..<blockStart]
        var block = Array(lines[blockStart...])
        // A table in the making: its trailing run of `|` lines is its head and perhaps a
        // delimiter row still arriving.
        let pipes = block.reversed().prefix(while: { $0.drop(while: { $0 == " " }).hasPrefix("|") })
            .count
        if pipes > 0 {
            let run = block.suffix(pipes)
            let delimiter = run.dropFirst().first
            let waiting =
                pipes == 1
                || (pipes == 2 && partial
                    && delimiter!.allSatisfy { "|:- ".contains($0) })
            if waiting {
                block.removeLast(pipes)
                return joined(kept, block, newline: false)
            }
            // A row begun and nothing in it yet ends the table as a paragraph of one
            // pipe: held back until its first cell has words.
            if partial, pipes > 2, block.last!.allSatisfy({ "| ".contains($0) }) {
                block.removeLast()
                return joined(kept, block, newline: false)
            }
        }
        return joined(kept, [Substring(closed(block.joined(separator: "\n")))], newline: !partial)
    }

    private static func joined(_ kept: ArraySlice<Substring>, _ block: [Substring], newline: Bool)
        -> String
    {
        let all = (kept + block).joined(separator: "\n")
        return newline && !all.isEmpty ? all + "\n" : all
    }

    /// One block's inline constructs closed at its end, innermost first: an open code
    /// span, then whatever emphasis or link opened before it. A delimiter opens when the
    /// next character is not a space and closes when the previous one is not (CommonMark's
    /// flanking rule, simplified to what decides a stream's tail).
    private static func closed(_ block: String) -> String {
        let characters = Array(block)
        var code: (at: Int, count: Int)?
        var open: [(at: Int, closer: String)] = []
        var index = 0
        while index < characters.count {
            let c = characters[index]
            if c == "\\" {
                index += 2
                continue
            }
            if c == "`" {
                let run = characters[index...].prefix(while: { $0 == "`" }).count
                if let current = code {
                    if current.count == run { code = nil }
                } else {
                    code = (index, run)
                }
                index += run
                continue
            }
            if code != nil {
                index += 1
                continue
            }
            if c == "*" || c == "~" {
                let run = characters[index...].prefix(while: { $0 == c }).count
                let token = String(repeating: c, count: run)
                let before = index > 0 ? characters[index - 1] : nil
                let after = index + run < characters.count ? characters[index + run] : nil
                if c == "*" || run == 2 {
                    if let before, !before.isWhitespace,
                        let last = open.lastIndex(where: { $0.closer == token })
                    {
                        open.removeSubrange(last...)
                    } else if after.map({ !$0.isWhitespace }) ?? true {
                        open.append((index, token))
                    }
                }
                index += run
                continue
            }
            if c == "]", index + 1 < characters.count, characters[index + 1] == "(" {
                open.append((index, ")"))
                index += 2
                continue
            }
            if c == ")", open.last?.closer == ")" {
                open.removeLast()
            }
            index += 1
        }
        var out = characters
        var closers = ""
        let unclosed =
            (code.map { [($0.at, String(repeating: "`", count: $0.count))] } ?? [])
            + open.reversed()
        for (at, closer) in unclosed {
            // An opener with nothing after it yet is dropped with what follows it; one
            // whose content has started is closed. A link is always closed: its words
            // are whole by then, and `[words]()` draws as the words.
            if closer != ")", out[(at + closer.count)...].allSatisfy(\.isWhitespace) {
                out.removeSubrange(at...)
                closers = ""
            } else {
                closers += closer
            }
        }
        var result = String(out)
        if !closers.isEmpty {
            while result.last?.isWhitespace == true { result.removeLast() }
            result += closers
        }
        return result
    }
}
