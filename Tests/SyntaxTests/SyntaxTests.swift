import SwiftUI
import Testing

@testable import Syntax

struct SyntaxTests {
    /// The exact shape that looked atrocious under the hand tokenizer: a
    /// shell line carrying a python heredoc. The grammar pass must color it
    /// (several distinct inks), and coloring may never rewrite a character.
    @Test func aHeredocScriptIsColoredAndCharacterExact() {
        let command = """
            cd ~/project; python3 - <<'EOF'
            def rep(a, b):
                global s
                assert s.count(a) == 1, a[:60]
                s = s.replace(a, b)
            EOF
            """
        let colored = Syntax.highlight(command, as: .shell)
        #expect(String(colored.characters) == command)
        let inks = Set(colored.runs.compactMap { $0.foregroundColor })
        #expect(inks.count >= 2, "one ink means the grammar pass did nothing: \(inks)")
    }

    /// The grammar's inks travel as data and paint the same text the same
    /// way where no engine runs; they never paint other text.
    @Test func colorsTravelAsDataAndPaintExactly() throws {
        let command = "find .build -name \"*.o\" -delete && echo \"freed in $HOME\""
        let colors = try #require(Syntax.colors(command, as: .shell))
        let painted = try #require(colors.paint(command))
        #expect(String(painted.characters) == command)
        #expect(Set(painted.runs.compactMap { $0.foregroundColor }).count >= 2)
        #expect(colors.paint(command + "x") == nil)
        #expect(Syntax.colors("+ a\n- b", as: .diff) == nil)
        #expect(try JSONEncoder().encode(colors).count < 1024)
    }

    @Test func aSingleShellLineIsColoredAsShell() {
        let command = "rg -n \"pattern\" src | head -5"
        let colored = Syntax.highlight(command, as: .shell)
        #expect(String(colored.characters) == command)
        #expect(!Set(colored.runs.compactMap { $0.foregroundColor }).isEmpty)
    }

    @Test func diffAndPlainStayExact() {
        let diff = "@@ a.txt\n- old\n+ new"
        #expect(String(Syntax.highlight(diff, as: .diff).characters) == diff)
        let plain = "file_path: /tmp/x\ncontent: hello"
        #expect(Syntax.highlight(plain, as: .plain) == AttributedString(plain))
    }
}
