import SwiftUI
import Testing

@testable import Syntax

struct SyntaxTests {
    /// The exact shape that looked atrocious under the hand tokenizer: a
    /// shell line carrying a python heredoc. The grammar pass must color it
    /// (several distinct inks), and coloring may never rewrite a character.
    @Test(arguments: [Syntax.Appearance.light, .dark])
    func aHeredocScriptIsColoredAndCharacterExact(_ appearance: Syntax.Appearance) {
        let command = """
            cd ~/project; python3 - <<'EOF'
            def rep(a, b):
                global s
                assert s.count(a) == 1, a[:60]
                s = s.replace(a, b)
            EOF
            """
        let colored = Syntax.highlight(command, as: .shell, on: appearance)
        #expect(String(colored.characters) == command)
        let inks = Set(colored.runs.compactMap { $0.foregroundColor })
        #expect(inks.count >= 2, "one ink means the grammar pass did nothing: \(inks)")
    }

    /// Each appearance's inks read on its own ground: on white, no ink is
    /// as pale as a dark theme's (the light-mode text that vanished into a
    /// light-gray box was this).
    @Test func eachAppearanceInksReadOnItsGround() throws {
        let command = "swift test --filter InboxTests 2>&1 | tail -40 && echo \"done in $HOME\""
        let light = try #require(Syntax.colors(command, as: .shell, on: .light))
        let dark = try #require(Syntax.colors(command, as: .shell, on: .dark))
        #expect(light.palette != dark.palette)
        for hex in light.palette {
            #expect(Self.luminance(hex) < 0.5, "\(hex) is too pale for a light ground")
        }
        for hex in dark.palette {
            #expect(Self.luminance(hex) > 0.2, "\(hex) is too dim for a dark ground")
        }
    }

    /// The grammar's inks travel as data and paint the same text the same
    /// way where no engine runs; they never paint other text.
    @Test func colorsTravelAsDataAndPaintExactly() throws {
        let command = "find .build -name \"*.o\" -delete && echo \"freed in $HOME\""
        let colors = try #require(Syntax.colors(command, as: .shell, on: .dark))
        let painted = try #require(colors.paint(command))
        #expect(String(painted.characters) == command)
        #expect(Set(painted.runs.compactMap { $0.foregroundColor }).count >= 2)
        #expect(colors.paint(command + "x") == nil)
        #expect(Syntax.colors("+ a\n- b", as: .diff, on: .dark) == nil)
        #expect(try JSONEncoder().encode(colors).count < 1024)
    }

    @Test func aSingleShellLineIsColoredAsShell() {
        let command = "rg -n \"pattern\" src | head -5"
        let colored = Syntax.highlight(command, as: .shell, on: .light)
        #expect(String(colored.characters) == command)
        #expect(!Set(colored.runs.compactMap { $0.foregroundColor }).isEmpty)
    }

    @Test func diffAndPlainStayExact() {
        let diff = "@@ a.txt\n- old\n+ new"
        #expect(String(Syntax.highlight(diff, as: .diff, on: .light).characters) == diff)
        let plain = "file_path: /tmp/x\ncontent: hello"
        #expect(Syntax.highlight(plain, as: .plain, on: .dark) == AttributedString(plain))
    }

    /// Relative luminance of `#rrggbb` (WCAG).
    static func luminance(_ hex: String) -> Double {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        func channel(_ shift: Int) -> Double {
            let c = Double((value >> shift) & 0xff) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}
