#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import Ink

    // The tip's panel, pinned against what broke it: a panel shown at 0x0 (sized
    // from a view the panel had already shrunk), a panel half a point wider than
    // its chip (windows are framed in whole points), and now its timing: the
    // first tip waits, the next one shows at once. Shown for real, in a real
    // window, for each shape the words can take.

    @MainActor
    private func window() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: 480, height: 200), styleMask: [.titled],
            backing: .buffered, defer: false)
    }

    private func ask(_ text: String, prefers: VerticalEdge = .bottom, edge: VerticalEdge? = nil)
        -> InkTipAsk
    {
        InkTipAsk(text: text, tint: .secondary, edge: edge, prefers: prefers)
    }

    /// Past the first tip's wait, with room for a busy machine.
    private let pastWait: Duration = InkTipPresenter.wait + .milliseconds(250)

    // One presenter for the app, so these run one at a time, never beside each
    // other: two tests showing tips at once would each see the other's panel.
    @Suite(.serialized) struct InkTip {

        @MainActor
        @Test(
            .serialized,
            arguments: [
                "0x71C7656EC7ab88b098defB751B7401B5f6d8976F",  // a value: one line
                "/Users/someone/Projects/garden/assets/photos/2025/greenhouse-tomatoes.jpg",
                "Copy",  // a word
                "Copy the savings address",  // prose that fits a line
                "Copies the savings address, e.g. for a transfer. Exactly as stored, never retyped.",
            ])
        func tipPanelTakesTheChipSize(text: String) async throws {
            let w = window()
            let anchor = InkTipAnchorView(frame: NSRect(x: 40, y: 90, width: 180, height: 16))
            try #require(w.contentView).addSubview(anchor)

            InkTipPresenter.shared.show(ask(text), under: anchor)
            try await Task.sleep(for: pastWait)
            let panel = InkTipPresenter.shared.panel
            #expect(panel.isVisible)
            // The chip plus 12 points of shadow on each side: never collapsed.
            #expect(panel.frame.width > 24 + 20 && panel.frame.height > 24 + 10)
            #expect(panel.frame.width == panel.frame.width.rounded())
            InkTipPresenter.shared.hide(anchor)
            #expect(!panel.isVisible)
        }

        // Prose is as wide as its longest line: two words make a small chip, not
        // one stretched to the reading width; a long sentence stops at that width.
        @MainActor
        @Test func proseHugsItsWords() async throws {
            let w = window()
            let anchor = InkTipAnchorView(frame: NSRect(x: 40, y: 90, width: 180, height: 16))
            try #require(w.contentView).addSubview(anchor)
            func width(_ text: String) async throws -> CGFloat {
                InkTipPresenter.shared.show(ask(text), under: anchor)
                try await Task.sleep(for: pastWait)
                defer { InkTipPresenter.shared.hide(anchor) }
                return InkTipPresenter.shared.panel.frame.width
            }
            // Around the words: shadow 12 + padding 11 + dot 6 + spacing 6, then
            // padding 11 + shadow 12.
            let around: CGFloat = 12 + 11 + 6 + 6 + 11 + 12
            let short = try await width("add clips")
            let long = try await width(
                "What the punch sees across the move. Click to play from there and watch it land")
            #expect(short < around + 80, "two words took \(short - around) points")
            #expect(long <= around + InkTipChip.readingWidth + 1)
            #expect(
                long > around + InkTipChip.readingWidth - 40, "a long sentence wraps at the cap")
        }

        // The first tip waits (a sweep across a bar never strobes); once one has
        // shown, the next shows at once.
        @MainActor
        @Test func firstWaitsThenWarm() async throws {
            let w = window()
            let a = InkTipAnchorView(frame: NSRect(x: 20, y: 90, width: 100, height: 16))
            let b = InkTipAnchorView(frame: NSRect(x: 200, y: 90, width: 100, height: 16))
            try #require(w.contentView).addSubview(a)
            try #require(w.contentView).addSubview(b)
            let panel = InkTipPresenter.shared.panel
            try await Task.sleep(for: InkTipPresenter.warm + .milliseconds(100))

            InkTipPresenter.shared.show(ask("a"), under: a)
            #expect(!panel.isVisible, "the first tip shows at once")
            try await Task.sleep(for: pastWait)
            #expect(panel.isVisible)

            InkTipPresenter.shared.hide(a)
            InkTipPresenter.shared.show(ask("b"), under: b)
            #expect(panel.isVisible, "the next tip waits")
            InkTipPresenter.shared.hide(b)
        }

        // A pointer that leaves before the wait is over never sees a tip.
        @MainActor
        @Test func leavingBeforeTheWaitShowsNothing() async throws {
            let w = window()
            let a = InkTipAnchorView(frame: NSRect(x: 20, y: 90, width: 100, height: 16))
            try #require(w.contentView).addSubview(a)
            try await Task.sleep(for: InkTipPresenter.warm + .milliseconds(100))
            InkTipPresenter.shared.show(ask("a"), under: a)
            InkTipPresenter.shared.hide(a)
            try await Task.sleep(for: pastWait)
            #expect(!InkTipPresenter.shared.panel.isVisible)
        }

        // Below the element by default, above where the section prefers it; an edge
        // pins the side.
        @MainActor
        @Test func sides() async throws {
            let w = window()
            let a = InkTipAnchorView(frame: NSRect(x: 40, y: 90, width: 180, height: 16))
            try #require(w.contentView).addSubview(a)
            let element = w.convertToScreen(a.convert(a.bounds, to: nil))
            let panel = InkTipPresenter.shared.panel

            func shown(_ asked: InkTipAsk) async throws -> NSRect {
                InkTipPresenter.shared.show(asked, under: a)
                try await Task.sleep(for: pastWait)
                defer { InkTipPresenter.shared.hide(a) }
                return panel.frame
            }
            #expect(try await shown(ask("below")).maxY <= element.minY + 12, "default: below")
            #expect(
                try await shown(ask("above", prefers: .top)).minY >= element.maxY - 12,
                "preferring top: above")
            #expect(
                try await shown(ask("pinned", prefers: .top, edge: .bottom)).maxY <= element.minY
                    + 12)
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
        @Test func oneTipAtATime() async throws {
            let w = window()
            let a = InkTipAnchorView(frame: NSRect(x: 20, y: 90, width: 100, height: 16))
            let b = InkTipAnchorView(frame: NSRect(x: 200, y: 90, width: 100, height: 16))
            try #require(w.contentView).addSubview(a)
            try #require(w.contentView).addSubview(b)

            InkTipPresenter.shared.show(ask("a"), under: a)
            try await Task.sleep(for: pastWait)
            InkTipPresenter.shared.show(ask("b"), under: b)
            InkTipPresenter.shared.hide(a)
            #expect(InkTipPresenter.shared.panel.isVisible)
            InkTipPresenter.shared.hide(b)
            #expect(!InkTipPresenter.shared.panel.isVisible)
        }
    }
#endif
