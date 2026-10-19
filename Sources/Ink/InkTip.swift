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
// Two looks, set once for a window or a section (`.inkTipStyle`), the way a
// theme is: `.glass` (default), a coloured dot and the words on Liquid Glass
// tinted with the subject's colour, below the element; `.bubble`, a dark mono
// bubble for HUD and media chrome, above it. Each flips to the other side when
// the screen has no room; `edge:` pins a side for one tip.
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

/// How tips look and which side they prefer, for everything inside
/// `.inkTipStyle(_:)`.
public struct InkTipStyle: Sendable, Equatable {
    public enum Look: Sendable, Equatable {
        /// A coloured dot and the words on Liquid Glass tinted with the subject's colour.
        case glass
        /// Light mono words on a dark bubble: HUD and media chrome.
        case bubble
    }

    public let look: Look
    /// The side a tip takes when there is room; the other when there is not.
    public let prefers: VerticalEdge

    public init(look: Look, prefers: VerticalEdge) {
        self.look = look
        self.prefers = prefers
    }

    public static let glass = InkTipStyle(look: .glass, prefers: .bottom)
    public static let bubble = InkTipStyle(look: .bubble, prefers: .top)
}

extension View {
    /// This element's tip, the only one on its hover. nil: nothing to say, and the
    /// hover stays free for a tip inside. Under a tip that already speaks, it says
    /// nothing. `edge` pins the side, which otherwise follows the style and the
    /// room on screen.
    public func inkTip(_ text: String?, tint: Color = .secondary, edge: VerticalEdge? = nil)
        -> some View
    {
        modifier(InkTipSource(text: text, tint: tint, edge: edge))
    }

    /// How every tip inside looks and which side it prefers.
    public func inkTipStyle(_ style: InkTipStyle) -> some View {
        environment(\.inkTipStyle, style)
    }
}

extension EnvironmentValues {
    /// A tip above has claimed the hover: tips below say nothing.
    @Entry var inkTipClaimed = false
    @Entry var inkTipStyle = InkTipStyle.glass
}

/// One tip, as asked: what it says and how it is drawn.
struct InkTipAsk: Equatable {
    let text: String
    let tint: Color
    let edge: VerticalEdge?
    let style: InkTipStyle
}

private struct InkTipSource: ViewModifier {
    let text: String?
    let tint: Color
    let edge: VerticalEdge?
    @Environment(\.inkTipClaimed) private var claimed
    @Environment(\.inkTipStyle) private var style

    func body(content: Content) -> some View {
        let said = claimed ? nil : text
        let ask = said.map { InkTipAsk(text: $0, tint: tint, edge: edge, style: style) }
        let claiming = content.environment(\.inkTipClaimed, claimed || said != nil)
        #if os(macOS)
            claiming.background(InkTipAnchor(ask: ask))
        #else
            claiming.modifier(InkTipOverlay(ask: ask))
        #endif
    }
}

/// The chip, in its look, measured by what the words are.
struct InkTipChip: View {
    let text: String
    let tint: Color
    let look: InkTipStyle.Look

    init(text: String, tint: Color, look: InkTipStyle.Look = .glass) {
        self.text = text
        self.tint = tint
        self.look = look
    }

    /// The width prose wraps at: a glance, not a paragraph.
    static let readingWidth: CGFloat = 220
    /// The bubble's mono runs wider per word.
    static let bubbleWidth: CGFloat = 260

    var body: some View {
        switch look {
        case .glass:
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6).padding(.top, 3)
                words(width: Self.readingWidth, alignment: .leading)
                    .font(.caption2).foregroundStyle(.primary)
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .glassEffect(.regular.tint(tint.opacity(0.10)), in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
        case .bubble:
            words(width: Self.bubbleWidth, alignment: .center)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                    .black.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    @ViewBuilder private func words(width: CGFloat, alignment: Alignment) -> some View {
        if Self.isToken(text) {
            Text(verbatim: text).lineLimit(1).fixedSize()
        } else {
            Text(verbatim: Self.sentences(text).joined(separator: "\n"))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: width, alignment: alignment)
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
                chip: InkTipChip(text: ask.text, tint: ask.tint, look: ask.style.look))
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
            switch ask.edge ?? ask.style.prefers {
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
            let above = (ask?.edge ?? ask?.style.prefers) == .top
            content
                .inkHover($hovered)
                .overlay(alignment: above ? .top : .bottom) {
                    if hovered, let ask {
                        InkTipChip(text: ask.text, tint: ask.tint, look: ask.style.look)
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
