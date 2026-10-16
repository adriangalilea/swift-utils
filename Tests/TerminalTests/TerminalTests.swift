import Testing

@testable import Terminal

// Width counts terminal cells: escapes are free, a CJK character or an
// emoji-presented cluster takes two, a ZWJ family is one cluster.
@Test func widthCountsCells() {
    #expect(width("abc") == 3)
    #expect(width(ANSI.bold + "abc" + ANSI.reset) == 3)
    #expect(width("日本") == 4)
    #expect(width("👨‍👩‍👧") == 2)
    #expect(width("🇪🇸") == 2)
    #expect(width("é") == 1)
}

// Clipping keeps styling, closes it, and never splits a wide character.
@Test func clipIsAnsiAware() {
    #expect(clip("abcdef", 4) == "abc…")
    #expect(clip("abc", 4) == "abc")
    #expect(clip(ANSI.dim + "abcdef", 4) == ANSI.dim + "abc…" + ANSI.reset)
    #expect(clip("日本語", 4) == "日…")
}

@Test func paletteOffIsPlain() {
    let plain = Palette(enabled: false)
    #expect(plain.head("x") == "x")
    #expect(Palette(enabled: true).muted("x") == ANSI.dim + "x" + ANSI.reset)
    #expect(Palette.detected(["NO_COLOR": "1"]) == false)
    #expect(Palette.detected(["FORCE_COLOR": "1", "NO_COLOR": "1"]) == true)
    #expect(Palette.detected(["TERM": "dumb"]) == false)
}

// Columns align on visible width; no line ends in whitespace.
@Test func tableAligns() {
    #expect(table([["a", "1"], ["bbb", "22"]], align: ["l", "r"]) == "a     1\nbbb  22")
    #expect(table([["a", ""], ["bbb", "x"]]) == "a\nbbb  x")
    #expect(indent("a\nb", 2) == "  a\n  b")
    #expect(tree("root", ["x", "y"]) == "root\n  x\n  y")
}
