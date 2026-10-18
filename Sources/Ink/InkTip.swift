import SwiftUI

// The studio's ONE tooltip, designed in hollow and moved here so every app
// wears it: a colored dot and wrapped text on Liquid Glass tinted with the
// subject's color, instant on hover (state-driven, never the system
// tooltip's delay or its flat black chip). Every sentence on its own line:
// a tooltip is glanced, not read.
//
// Two ways to float it, one look:
//  - `.inkTip("...")` on an element inside an `.inkTipSurface()` container:
//    the element publishes its bounds and text as an anchor preference and
//    the surface floats the chip BELOW it, clamped to the container. For
//    dense layouts (grids, cards): the chip rides above every sibling.
//  - `.inkFloatingTip("...")` (macOS) floats the chip in its own borderless
//    panel anchored in screen coordinates: for views a preference cannot
//    reach a surface from (toolbar items), and for small floating panels
//    (a HUD), whose bounds would clip an in-hierarchy chip.

struct InkTipChip: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6).padding(.top, 3)
            Text(text.replacingOccurrences(of: ". ", with: ".\n"))
                .font(.caption2).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 220, alignment: .leading)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .glassEffect(.regular.tint(tint.opacity(0.10)), in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
    }
}

private struct InkTipValue {
    var anchor: Anchor<CGRect>
    var text: String
    var tint: Color
}

private struct InkTipKey: PreferenceKey {
    static let defaultValue: InkTipValue? = nil
    static func reduce(value: inout InkTipValue?, nextValue: () -> InkTipValue?) {
        if let next = nextValue() { value = next }
    }
}

private struct InkTipSource: ViewModifier {
    let text: String?
    let tint: Color
    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .onHover { hover = $0 }
            .anchorPreference(key: InkTipKey.self, value: .bounds) { anchor in
                guard hover, let text else { return nil }
                return InkTipValue(anchor: anchor, text: text, tint: tint)
            }
    }
}

private struct InkTipSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(InkTipKey.self) { tip in
                if let tip {
                    GeometryReader { geo in
                        let r = geo[tip.anchor]
                        InkTipChip(text: tip.text, tint: tip.tint)
                            .position(
                                x: min(max(r.midX, 120), geo.size.width - 120), y: r.maxY + 22
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
            // A surface OWNS its tips: a nested surface never draws the
            // same chip twice.
            .transformPreference(InkTipKey.self) { $0 = nil }
    }
}

extension View {
    /// This element's tip, floated by the nearest `inkTipSurface()`. nil:
    /// nothing to say.
    public func inkTip(_ text: String?, tint: Color = .secondary) -> some View {
        modifier(InkTipSource(text: text, tint: tint))
    }

    /// The container that floats its elements' `inkTip`s.
    public func inkTipSurface() -> some View {
        modifier(InkTipSurface())
    }
}

#if os(macOS)
    import AppKit

    extension View {
        /// The tip in its own floating panel, anchored below this element on
        /// screen.
        public func inkFloatingTip(_ text: String?, tint: Color = .secondary) -> some View {
            background(InkTipAnchor(text: text, tint: tint))
        }
    }

    // Everything (hover, show, hide) lives in ONE AppKit view with its own
    // tracking area, deliberately not SwiftUI's onHover: a host that rebuilds
    // its item views never delivers the pending hover exit, which strands the
    // chip. An NSView is told when it leaves its window and when it goes, so
    // the chip cannot outlive its anchor.
    private struct InkTipAnchor: NSViewRepresentable {
        let text: String?
        let tint: Color

        func makeNSView(context: Context) -> InkTipAnchorView { InkTipAnchorView() }
        func updateNSView(_ view: InkTipAnchorView, context: Context) {
            view.text = text
            view.tint = tint
        }
    }

    final class InkTipAnchorView: NSView {
        var text: String?
        var tint: Color = .secondary
        private var panel: NSPanel?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            // `.activeAlways`: a HUD's nonactivating panel belongs to an app
            // that is usually not the active one.
            // `.inVisibleRect`: the area follows the view's size (registered
            // before layout it was zero-sized, and no hover ever arrived).
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: self))
        }

        override func mouseEntered(with event: NSEvent) { show() }
        override func mouseExited(with event: NSEvent) { hide() }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil { hide() }
        }
        deinit { panel?.orderOut(nil) }

        private func show() {
            guard let text, let window else { return }
            // Measured as it will be drawn: the width proposed (so the text
            // wraps at the chip's cap before it is measured), the height it
            // then needs, and room around it for the shadow, which draws
            // outside the chip and was clipped by a panel cut to the chip.
            let rootView = InkTipChip(text: text, tint: tint)
            let size = NSHostingController(rootView: rootView).sizeThatFits(
                in: NSSize(width: 260, height: 10_000))
            let shadow: CGFloat = 12
            let chip = NSHostingView(rootView: rootView)
            // A fixed-frame container between the hosting view and the
            // panel: a hosting view that owns a window installs its own
            // sizing constraints and re-grows the panel after setFrame.
            let container = NSView(
                frame: NSRect(
                    origin: .zero,
                    size: NSSize(width: size.width + shadow * 2, height: size.height + shadow * 2)))
            chip.frame = NSRect(origin: NSPoint(x: shadow, y: shadow), size: size)
            chip.autoresizingMask = []
            container.addSubview(chip)

            // Below the element; above it when the screen has no room below
            // (a HUD near the Dock). Positions are the chip's; the panel is
            // the chip plus its shadow margin.
            let anchor = window.convertToScreen(convert(bounds, to: nil))
            var x = anchor.midX - size.width / 2
            var y = anchor.minY - 8 - size.height
            if let screen = window.screen?.visibleFrame {
                x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
                if y < screen.minY + 4 { y = anchor.maxY + 8 }
            }
            let origin = NSPoint(x: x - shadow, y: y - shadow)

            if panel == nil {
                let p = NSPanel(
                    contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: true)
                p.isOpaque = false
                p.backgroundColor = .clear
                p.hasShadow = false
                p.isReleasedWhenClosed = false
                p.ignoresMouseEvents = true
                // Above a status-bar HUD too.
                p.level = .popUpMenu
                p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel = p
            }
            panel!.contentView = container
            panel!.setFrame(NSRect(origin: origin, size: container.frame.size), display: true)
            panel!.orderFront(nil)
        }

        private func hide() { panel?.orderOut(nil) }
    }
#endif
