#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import Ink

    // The tip's panel, pinned against what broke it: a panel shown at 0x0 (sized
    // from a view the panel had already shrunk), and a panel half a point wider
    // than its chip (windows are framed in whole points). Shown for real, in a
    // real window, for each shape the words can take.
    @MainActor
    @Test(arguments: [
        "0x71C7656EC7ab88b098defB751B7401B5f6d8976F",  // a value: one line
        "/Users/someone/Projects/garden/assets/photos/2025/greenhouse-tomatoes.jpg",
        "Copy",  // a word
        "Copied",
        "Copy the savings address",  // prose that fits a line
        "Copies the savings address, e.g. for a transfer. Exactly as stored, never retyped.",
    ])
    func tipPanelTakesTheChipSize(text: String) throws {
        let window = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: 480, height: 200), styleMask: [.titled],
            backing: .buffered, defer: false)
        let anchor = InkTipAnchorView(frame: NSRect(x: 40, y: 90, width: 180, height: 16))
        try #require(window.contentView).addSubview(anchor)

        InkTipPresenter.shared.show(text, tint: .secondary, under: anchor)
        let panel = InkTipPresenter.shared.panel
        #expect(panel.isVisible)
        // The chip plus 12 points of shadow on each side: never collapsed.
        #expect(panel.frame.width > 24 + 20 && panel.frame.height > 24 + 10)
        #expect(panel.frame.width == panel.frame.width.rounded())

        InkTipPresenter.shared.hide(anchor)
        #expect(!panel.isVisible)
    }

    // A value stays whole on one line; prose is cut into its sentences, an
    // abbreviation inside one kept.
    @Test func wordsTakeTheirOwnShape() {
        #expect(InkTipChip.isToken("0x71C7656EC7ab88b098defB751B7401B5f6d8976F"))
        #expect(!InkTipChip.isToken("Copy the savings address"))
        #expect(
            InkTipChip.sentences(
                "Copies the savings address, e.g. for a transfer. Exactly as stored, never retyped."
            )
                == [
                    "Copies the savings address, e.g. for a transfer.",
                    "Exactly as stored, never retyped.",
                ])
    }

    // One tip at a time: showing another replaces the first, and the first one's
    // late exit does not hide the second.
    @MainActor
    @Test func oneTipAtATime() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: 480, height: 200), styleMask: [.titled],
            backing: .buffered, defer: false)
        let a = InkTipAnchorView(frame: NSRect(x: 20, y: 90, width: 100, height: 16))
        let b = InkTipAnchorView(frame: NSRect(x: 200, y: 90, width: 100, height: 16))
        try #require(window.contentView).addSubview(a)
        try #require(window.contentView).addSubview(b)

        InkTipPresenter.shared.show("a", tint: .secondary, under: a)
        InkTipPresenter.shared.show("b", tint: .secondary, under: b)
        InkTipPresenter.shared.hide(a)
        #expect(InkTipPresenter.shared.panel.isVisible)
        InkTipPresenter.shared.hide(b)
        #expect(!InkTipPresenter.shared.panel.isVisible)
    }
#endif
