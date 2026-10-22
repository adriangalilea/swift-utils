import Testing

@testable import MarkdownText

struct MarkdownDocumentTests {
    typealias Doc = MarkdownDocument

    /// Every block keeps where it was written, so a reader can go back to the text.
    @Test func blocksKeepTheirSourcePositions() throws {
        let doc = Doc("# Title\n\nA paragraph\nover two lines.\n\n- one\n- two\n")
        #expect(doc.blocks.count == 3)
        #expect(doc.blocks[0].span.start == .init(line: 1, column: 1))
        #expect(doc.blocks[1].span.start.line == 3)
        #expect(doc.blocks[1].span.end.line == 4)
        guard case .list(let list) = doc.blocks[2].kind else {
            Issue.record("not a list: \(doc.blocks[2].kind)")
            return
        }
        #expect(list.items.map(\.span.start.line) == [6, 7])
        guard case .heading(1, let words) = doc.blocks[0].kind else {
            Issue.record("not a heading")
            return
        }
        let span = try #require(words.first?.span)
        #expect(span.start == .init(line: 1, column: 3))
    }

    /// Front matter is its own value, and the body's positions still count from the
    /// text's first line.
    @Test func frontMatterIsKeptApartAndPositionsCountFromTheTop() {
        let doc = Doc("---\ntitle: x\n---\n# Body\n")
        #expect(doc.frontMatter == .init(format: .yaml, text: "title: x"))
        #expect(doc.blocks.count == 1)
        #expect(doc.blocks[0].span.start.line == 4)
        #expect(Doc("---\nnever closed\n").frontMatter == nil)
    }

    /// GitHub's extensions are all read: a table with its alignments, a strike, a task
    /// list, a bare URL as a link, a footnote.
    @Test func githubExtensionsArePresent() {
        let doc = Doc(
            """
            | a | b |
            |:--|--:|
            | 1 | 2 |

            ~~gone~~ and ~5 min, see https://example.com and www.apple.com. A note[^n].

            - [x] done
            - [ ] open

            [^n]: The note.
            """)
        guard case .table(let table) = doc.blocks[0].kind else {
            Issue.record("no table: \(doc.blocks[0].kind)")
            return
        }
        #expect(table.alignments == [.leading, .trailing])
        #expect(table.head.map(\.content.plainText) == ["a", "b"])
        #expect(table.rows.map { $0.map(\.content.plainText) } == [["1", "2"]])

        guard case .paragraph(let words) = doc.blocks[1].kind else {
            Issue.record("no paragraph")
            return
        }
        #expect(words.contains { if case .strikethrough = $0.kind { true } else { false } })
        // One tilde is "about", never a strike.
        #expect(words.plainText.contains("~5 min"))
        let links = words.compactMap { if case .link(let url, _, _) = $0.kind { url } else { nil } }
        #expect(links == ["https://example.com", "http://www.apple.com"])
        #expect(words.contains { if case .footnote("n", 1) = $0.kind { true } else { false } })

        guard case .list(let list) = doc.blocks[2].kind else {
            Issue.record("no list")
            return
        }
        #expect(list.items.map(\.checked) == [true, false])
        #expect(doc.footnotes.map(\.label) == ["n"])
        #expect(doc.footnotes.first?.blocks.first.map(\.plainText) == "The note.")
    }

    @Test func codeBlocksNameTheirLanguage() {
        let doc = Doc("```swift title=x\nlet a = 1\n```\n\n    indented\n")
        #expect(
            doc.blocks.map(\.kind) == [
                .code(language: "swift", info: "swift title=x", text: "let a = 1"),
                .code(language: nil, info: "", text: "indented"),
            ])
    }

    /// Only the web, mail and a phone become live links.
    @Test func onlySafeLinksAreFollowed() {
        #expect(Doc.link("https://a.b/c") != nil)
        #expect(Doc.link("mailto:a@b.c") != nil)
        #expect(Doc.link("javascript:alert(1)") == nil)
        #expect(Doc.link("file:///etc/passwd") == nil)
        #expect(Doc.link("shortcuts://run") == nil)
        #expect(Doc.link("relative/path") == nil)
    }

    // MARK: - streaming

    /// A stream cut anywhere parses, and never shows the syntax it is waiting on.
    @Test func aStreamCutAnywhereParses() {
        let full = """
            # Plan

            Some **bold words** and `code` and [a link](https://example.com).

            | col | other |
            |-----|-------|
            | 1   | 2     |

            ```python
            print("hi")
            ```

            - item *one*
              - nested
            """
        for end in full.indices {
            let doc = Doc(String(full[..<end]), streaming: true)
            for block in doc.blocks {
                if case .paragraph(let words) = block.kind {
                    let text = words.plainText
                    #expect(
                        !text.contains("**"),
                        "raw ** at cut \(full.distance(from: full.startIndex, to: end)): \(text)")
                    #expect(!text.contains("]("), "raw link at cut: \(text)")
                    #expect(!text.contains("`"), "a raw backtick at cut: \(text)")
                    #expect(!text.hasPrefix("|"), "a table head as a paragraph: \(text)")
                }
            }
        }
    }

    @Test func settlingClosesOrHoldsBack() {
        #expect(Doc.settled("Some **bold") == "Some **bold**")
        #expect(Doc.settled("Some **") == "Some ")
        #expect(Doc.settled("run `ls -") == "run `ls -`")
        #expect(Doc.settled("see [docs](https://exa") == "see [docs](https://exa)")
        #expect(Doc.settled("intro\n\n| a | b |") == "intro\n")
        #expect(Doc.settled("intro\n\n| a | b |\n|--") == "intro\n")
        #expect(Doc.settled("| a | b |\n|---|---|\n") == "| a | b |\n|---|---|\n")
        #expect(
            Doc.settled("| a | b |\n|---|---|\n| 1 | 2 |\n| ") == "| a | b |\n|---|---|\n| 1 | 2 |")
        #expect(Doc.settled("```py\nx = **2") == "```py\nx = **2")
        #expect(Doc.settled("2 ** 3 is eight") == "2 ** 3 is eight")
        #expect(Doc.settled("**done**\n") == "**done**\n")
        #expect(Doc.settled("`a` and *it") == "`a` and *it*")
    }

    /// A complete text settles to itself: streaming changes nothing once it is whole.
    @Test(arguments: [
        "plain words", "**bold** and *it* and `code`", "- a\n- b\n", "| a |\n|---|\n| 1 |\n",
        "```\ncode\n```\n",
    ])
    func aWholeTextSettlesToItself(_ text: String) {
        #expect(Doc.settled(text) == text)
    }
}
