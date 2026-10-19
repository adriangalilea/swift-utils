import NaturalLanguage
import SwiftUI

// The studio's ONE tooltip, designed in hollow and moved here so every app
// wears it: a colored dot and the words on Liquid Glass tinted with the
// subject's color, instant on hover (never the system tooltip's delay or its
// flat black chip).
//
// `.inkTip("...")` is the only call, and it works anywhere:
//  - macOS: ONE panel for the whole app, floated below the hovered element (above
//    it when the screen has no room below), over every window and never clipped
//    by one. One presenter owns it, so one tip shows at a time by construction,
//    and a tip whose words change while it shows (Copy, then Copied) changes in
//    place.
//  - iOS / iPadOS: a pointer's hover draws the chip under the element; a touch
//    hovers nothing and shows none.
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
    /// nothing.
    public func inkTip(_ text: String?, tint: Color = .secondary) -> some View {
        modifier(InkTipSource(text: text, tint: tint))
    }
}

extension EnvironmentValues {
    /// A tip above has claimed the hover: tips below say nothing.
    @Entry var inkTipClaimed = false
}

private struct InkTipSource: ViewModifier {
    let text: String?
    let tint: Color
    @Environment(\.inkTipClaimed) private var claimed

    func body(content: Content) -> some View {
        let said = claimed ? nil : text
        let claiming = content.environment(\.inkTipClaimed, claimed || said != nil)
        #if os(macOS)
            claiming.background(InkTipAnchor(text: said, tint: tint))
        #else
            claiming.modifier(InkTipOverlay(text: said, tint: tint))
        #endif
    }
}

/// The chip: the dot and the words, measured by what they are.
struct InkTipChip: View {
    let text: String
    let tint: Color

    /// The width prose wraps at: a glance, not a paragraph.
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
            Text(verbatim: Self.sentences(text).joined(separator: "\n"))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Self.readingWidth, alignment: .leading)
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
        let text: String?
        let tint: Color

        func makeNSView(context: Context) -> InkTipAnchorView { InkTipAnchorView() }
        func updateNSView(_ view: InkTipAnchorView, context: Context) {
            view.say(text, tint: tint)
        }
    }

    final class InkTipAnchorView: NSView {
        private var text: String?
        private var tint: Color = .secondary
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
        func say(_ text: String?, tint: Color) {
            self.text = text
            self.tint = tint
            guard hovered else { return }
            if let text {
                InkTipPresenter.shared.show(text, tint: tint, under: self)
            } else {
                InkTipPresenter.shared.hide(self)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            hovered = true
            if let text { InkTipPresenter.shared.show(text, tint: tint, under: self) }
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

        /// Room around the chip for its shadow, which draws outside it.
        private let shadow: CGFloat = 12
        /// From the element to the chip.
        private let gap: CGFloat = 8
        private let host = NSHostingController(rootView: InkTipStage(chip: nil))
        private weak var current: InkTipAnchorView?

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

        func show(_ text: String, tint: Color, under anchor: InkTipAnchorView) {
            guard let window = anchor.window else { return }
            current = anchor
            let chip = InkTipChip(text: text, tint: tint)
            host.rootView = InkTipStage(chip: chip)
            let screen = window.screen?.visibleFrame ?? .infinite
            // Measured as drawn: a token's own width, prose at its reading width.
            // Rounded up to whole points: a window is framed in whole points, so a
            // measured 317.5 became 318 and the panel and the chip disagreed.
            let fitted = host.sizeThatFits(
                in: NSSize(width: screen.width - 8, height: screen.height))
            let size = NSSize(width: fitted.width.rounded(.up), height: fitted.height.rounded(.up))
            assert(size.width > 0 && size.height > 0, "InkTip: a chip measured \(size)")

            let element = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            var x = element.midX - size.width / 2
            var y = element.minY - gap - size.height
            x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
            if y < screen.minY + 4 { y = element.maxY + gap }

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

        func hide(_ anchor: InkTipAnchorView) {
            guard current === anchor else { return }
            current = nil
            panel.orderOut(nil)
        }
    }

    /// What the one panel draws: the current chip, or nothing.
    struct InkTipStage: View {
        let chip: InkTipChip?
        var body: some View { chip }
    }
#else
    /// A pointer's hover on iPad: the chip under the element, drawn over what
    /// follows it.
    private struct InkTipOverlay: ViewModifier {
        let text: String?
        let tint: Color
        @State private var hovered = false

        func body(content: Content) -> some View {
            content
                .onHover { hovered = $0 }
                .overlay(alignment: .bottom) {
                    if hovered, let text {
                        InkTipChip(text: text, tint: tint)
                            .fixedSize()
                            .alignmentGuide(.bottom) { $0[.top] - 8 }
                            .allowsHitTesting(false)
                    }
                }
                .zIndex(hovered ? 1 : 0)
        }
    }
#endif
