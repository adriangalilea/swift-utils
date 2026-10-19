import NaturalLanguage
import SwiftUI

// The studio's ONE tooltip. `.inkTip("...")` is the only call, and it works
// anywhere:
//  - macOS: ONE panel for the whole app, floated beside the hovered element, over
//    every window and never clipped by one (a scroll view or a lane included).
//    One presenter owns it, so one tip shows at a time by construction, and words
//    that change while it shows change in place.
//  - iOS / iPadOS: a pointer's hover draws the chip beside the element; a touch
//    hovers nothing and shows none.
//
// It answers like the system's own: the first tip waits a beat (`wait`), so
// sweeping the pointer across a bar never strobes; once one has shown, the next
// shows at once for a moment (`warm`), so reading along a toolbar flows. A click
// is acting, not reading: it puts the tip away until the pointer leaves.
//
// One look: a coloured dot and the words on Liquid Glass tinted with the
// subject's colour, as wide as its longest line and never wider than a glance.
// A tip shows below its element; `.inkTipEdge(.top)` turns a window or a section
// the other way (chrome along a window's bottom edge), and it flips when the
// screen has no room. `edge:` pins a side for one tip.
//
// One hover, one tip: the outermost tip with something to say owns it. A tip with
// words claims the hover for everything inside it, so a component's own tip
// (MiddleTruncate's whole text, when cut) goes quiet under its caller's.
//
// The words decide their own shape: one unbroken token (an address, a hash, a
// path) stays whole on one line, never wrapped or hyphenated, since a break would
// change what it reads as; prose wraps at a reading width, each sentence on its
// own line, sentences found by the system's tokenizer: a tooltip is glanced, not
// read.

extension View {
    /// This element's tip, the only one on its hover. nil: nothing to say, and the
    /// hover stays free for a tip inside. Under a tip that already speaks, it says
    /// nothing. `edge` pins the side, which otherwise follows `inkTipEdge` and the
    /// room on screen. The words are the element's accessibility hint too, so a tip
    /// replaces `.help` whole.
    public func inkTip(_ text: String?, tint: Color = .secondary, edge: VerticalEdge? = nil)
        -> some View
    {
        modifier(InkTipSource(text: text, tint: tint, edge: edge))
    }

    /// The side every tip inside takes when the screen has room; the other when not.
    public func inkTipEdge(_ edge: VerticalEdge) -> some View {
        environment(\.inkTipPrefers, edge)
    }
}

extension EnvironmentValues {
    /// A tip above has claimed the hover: tips below say nothing.
    @Entry var inkTipClaimed = false
    @Entry var inkTipPrefers = VerticalEdge.bottom
}

/// One tip, as asked: what it says, its colour, and where it goes.
struct InkTipAsk: Equatable {
    let text: String
    let tint: Color
    /// A side pinned by the tip itself, kept even without room.
    let edge: VerticalEdge?
    let prefers: VerticalEdge
}

private struct InkTipSource: ViewModifier {
    let text: String?
    let tint: Color
    let edge: VerticalEdge?
    @Environment(\.inkTipClaimed) private var claimed
    @Environment(\.inkTipPrefers) private var prefers

    func body(content: Content) -> some View {
        let said = claimed ? nil : text
        let ask = said.map { InkTipAsk(text: $0, tint: tint, edge: edge, prefers: prefers) }
        // The words are also what assistive tech reads as the element's hint, as `.help` does.
        let claiming =
            content
            .accessibilityHint(Text(verbatim: said ?? ""), isEnabled: said != nil)
            .environment(\.inkTipClaimed, claimed || said != nil)
        #if os(macOS)
            claiming.background(InkTipAnchor(ask: ask))
        #else
            claiming.modifier(InkTipOverlay(ask: ask))
        #endif
    }
}

/// The chip, measured by what the words are.
struct InkTipChip: View {
    let text: String
    let tint: Color

    /// The widest prose runs before it wraps: a glance, not a paragraph.
    static let readingWidth: CGFloat = 220

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6).padding(.top, 3)
            words.font(.caption2).foregroundStyle(.primary)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .glassEffect(.regular.tint(tint.opacity(0.10)), in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
    }

    @ViewBuilder private var words: some View {
        if Self.isToken(text) {
            Text(verbatim: text).lineLimit(1).fixedSize()
        } else {
            InkTipMeasure(cap: Self.readingWidth) {
                Text(verbatim: Self.sentences(text).joined(separator: "\n"))
            }
        }
    }

    /// One unbroken run of characters: a value, kept whole.
    nonisolated static func isToken(_ text: String) -> Bool {
        !text.contains(where: \.isWhitespace)
    }

    nonisolated static func sentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { text[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// Prose as wide as its longest line, never wider than `cap`: a short tip hugs
/// its words, a long one wraps at the cap. Whatever width the host offers is
/// ignored, since a tip is measured by its words, not by the room around it.
struct InkTipMeasure: Layout {
    let cap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        assert(subviews.count == 1, "InkTipMeasure: one text, not \(subviews.count)")
        let natural = subviews[0].sizeThatFits(.unspecified)
        return subviews[0].sizeThatFits(
            ProposedViewSize(width: min(natural.width, cap), height: nil))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

#if os(macOS)
    import AppKit

    // The hover is read by an AppKit view of its own, deliberately not SwiftUI's
    // onHover: a host that rebuilds its item views never delivers the pending
    // hover exit, which strands the chip, while an NSView is told when it leaves
    // its window.
    private struct InkTipAnchor: NSViewRepresentable {
        let ask: InkTipAsk?

        func makeNSView(context: Context) -> InkTipAnchorView { InkTipAnchorView() }
        func updateNSView(_ view: InkTipAnchorView, context: Context) {
            view.say(ask)
        }
    }

    final class InkTipAnchorView: NSView {
        private var ask: InkTipAsk?
        private var hovered = false

        // Clipped, though it draws nothing: since macOS 14 a view does not clip to
        // its bounds by default, and its `visibleRect` then runs past them, to the
        // whole window for a view hosted in SwiftUI. An `.inVisibleRect` area then
        // covered the window, the pointer was inside it from the start, and no
        // `mouseEntered` ever came.
        override init(frame: NSRect) {
            super.init(frame: frame)
            clipsToBounds = true
        }

        required init?(coder: NSCoder) { fatalError("InkTipAnchorView is made in code") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        // Installed ONCE, when the view joins a window, and never rebuilt: replacing
        // it in `updateTrackingAreas` lost every hover under an element that redraws
        // when hovered (a Copy), the area being replaced the moment the pointer
        // entered it. `.inVisibleRect` follows the view's size by itself.
        // `.activeAlways`: a HUD's nonactivating panel belongs to an app that is
        // usually not the active one.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, trackingAreas.isEmpty else { return }
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: self))
        }

        /// New words, or none: shown in place while hovered.
        func say(_ ask: InkTipAsk?) {
            guard ask != self.ask else { return }
            self.ask = ask
            guard hovered else { return }
            if let ask {
                InkTipPresenter.shared.show(ask, under: self)
            } else {
                InkTipPresenter.shared.hide(self)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            hovered = true
            if let ask { InkTipPresenter.shared.show(ask, under: self) }
        }

        override func mouseExited(with event: NSEvent) {
            hovered = false
            InkTipPresenter.shared.hide(self)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                hovered = false
                InkTipPresenter.shared.hide(self)
            }
        }
    }

    /// The app's one tip: one panel, one current anchor. Showing a tip for one
    /// anchor replaces any other; hiding is asked by an anchor and only hides its
    /// own, so a late exit from the last element never hides the next one's.
    @MainActor
    final class InkTipPresenter {
        static let shared = InkTipPresenter()

        /// The first tip waits this long: a sweep across a bar never strobes.
        nonisolated static let wait: Duration = .milliseconds(350)
        /// After a tip has shown, the next shows at once for this long.
        nonisolated static let warm: Duration = .milliseconds(800)

        /// Room around the chip for its shadow, which draws outside it.
        private let shadow: CGFloat = 12
        /// From the element to the chip.
        private let gap: CGFloat = 8
        private let host = NSHostingController(rootView: InkTipStage(chip: nil))
        private weak var current: InkTipAnchorView?
        /// Clicked while its tip was up: it stays quiet until the pointer leaves.
        private weak var dismissed: InkTipAnchorView?
        private var pending: Task<Void, Never>?
        private var lastUp: ContinuousClock.Instant?
        private var clicks: Any?

        lazy var panel: NSPanel = {
            let p = NSPanel(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: true)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.isReleasedWhenClosed = false
            p.ignoresMouseEvents = true
            // Above a status-bar HUD too.
            p.level = .popUpMenu
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            // The hosting view never sizes the panel: the panel is set from the
            // chip's measurement, below.
            host.sizingOptions = []
            let stage = NSView()
            stage.addSubview(host.view)
            p.contentView = stage
            return p
        }()

        private var isWarm: Bool {
            panel.isVisible || lastUp.map { ContinuousClock.now - $0 < Self.warm } == true
        }

        func show(_ ask: InkTipAsk, under anchor: InkTipAnchorView) {
            guard anchor !== dismissed else { return }
            watchClicks()
            pending?.cancel()
            current = anchor
            if isWarm { return present(ask, under: anchor) }
            pending = Task { [weak self, weak anchor] in
                try? await Task.sleep(for: Self.wait)
                guard !Task.isCancelled, let self, let anchor, self.current === anchor else {
                    return
                }
                self.present(ask, under: anchor)
            }
        }

        func hide(_ anchor: InkTipAnchorView) {
            if dismissed === anchor { dismissed = nil }
            guard current === anchor else { return }
            putAway()
        }

        private func putAway() {
            pending?.cancel()
            current = nil
            if panel.isVisible { lastUp = .now }
            panel.orderOut(nil)
        }

        /// A click anywhere in the app is acting, not reading: the tip goes, and
        /// its element stays quiet until the pointer leaves it.
        private func watchClicks() {
            guard clicks == nil else { return }
            clicks = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let current = self.current else { return }
                    self.dismissed = current
                    self.putAway()
                }
                return event
            }
        }

        private func present(_ ask: InkTipAsk, under anchor: InkTipAnchorView) {
            guard let window = anchor.window else { return }
            host.rootView = InkTipStage(
                chip: InkTipChip(text: ask.text, tint: ask.tint))
            let screen = window.screen?.visibleFrame ?? .infinite
            // Measured as drawn: a token's own width, prose at its reading width.
            // Rounded up to whole points: a window is framed in whole points, so a
            // measured 317.5 became 318 and the panel and the chip disagreed.
            let fitted = host.sizeThatFits(
                in: NSSize(width: screen.width - 8, height: screen.height))
            let size = NSSize(width: fitted.width.rounded(.up), height: fitted.height.rounded(.up))
            assert(size.width > 0 && size.height > 0, "InkTip: a chip measured \(size)")

            // AppKit's y grows upward: below the element is a smaller y.
            let element = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let belowY = element.minY - gap - size.height
            let aboveY = element.maxY + gap
            let y: CGFloat
            switch ask.edge ?? ask.prefers {
            case .bottom where ask.edge != nil, .bottom where belowY >= screen.minY + 4:
                y = belowY
            case .bottom:
                y = aboveY
            case .top where ask.edge != nil, .top where aboveY + size.height <= screen.maxY - 4:
                y = aboveY
            case .top:
                y = belowY
            }
            var x = element.midX - size.width / 2
            x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)

            let frame = NSRect(
                x: (x - shadow).rounded(), y: (y - shadow).rounded(),
                width: size.width + shadow * 2,
                height: size.height + shadow * 2)
            host.view.frame = NSRect(origin: NSPoint(x: shadow, y: shadow), size: size)
            panel.setFrame(frame, display: true)
            assert(
                panel.frame.size == frame.size,
                "InkTip: the panel took \(panel.frame), not \(frame)")
            // Regardless: the host is often not the active app (a HUD over someone
            // else's window), and plain `orderFront` from an inactive app leaves the
            // chip behind that window.
            panel.orderFrontRegardless()
        }
    }

    /// What the one panel draws: the current chip, or nothing.
    struct InkTipStage: View {
        let chip: InkTipChip?
        var body: some View { chip }
    }
#else
    /// A pointer's hover on iPad: the chip beside the element, drawn over its
    /// neighbours. tvOS never hovers (`inkHover`), so it never shows there.
    private struct InkTipOverlay: ViewModifier {
        let ask: InkTipAsk?
        @State private var hovered = false

        func body(content: Content) -> some View {
            let above = (ask?.edge ?? ask?.prefers) == .top
            content
                .inkHover($hovered)
                .overlay(alignment: above ? .top : .bottom) {
                    if hovered, let ask {
                        InkTipChip(text: ask.text, tint: ask.tint)
                            .fixedSize()
                            .alignmentGuide(above ? .top : .bottom) {
                                above ? $0[.bottom] + 8 : $0[.top] - 8
                            }
                            .allowsHitTesting(false)
                    }
                }
                .zIndex(hovered ? 1 : 0)
        }
    }
#endif
