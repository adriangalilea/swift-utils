import SwiftUI

/// The walk's curve, the pages and their dots alike: 350 ms, ui's glide.
private let inkGlide = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.35)

/// A walk through pages, one at a time (an onboarding, a setup, a tour): the
/// page, and under it the way through. Back on the left (there on every page,
/// disabled on the first), the dots in the middle, the way on at the right (the
/// caller's, which keeps one button in one width for the same reason:
/// "Continue", "Skip"). An action about the page's own subject (allow this,
/// try that) belongs IN the page, beside the words that explain it; the
/// footer only walks, so its right end always means "go on". Pages slide in
/// the direction walked; ← and → walk too, ⏎ is the action marked
/// `.keyboardShortcut(.defaultAction)`. On the host's material
/// (`.inkMaterial`), in Ink's buttons.
///
/// The dots are the markers, and can carry each page's state: `marker` gives
/// a page its colour (a grant to allow yellow, one allowed green; nil, the
/// neutral ink), so the row reads as a checklist. `jump` says which dots are
/// a click away: `.seen` (the pages already walked; the way forward is the
/// page's own action) or `.any` (every page is its own stop, a checklist the
/// person picks from).
///
///     InkPages(page: $page, count: 4) { index in
///         Page(index)
///     } action: { index in
///         Button("Continue") { page += 1 }.buttonStyle(.inkProminent)
///     }
public struct InkPages<Content: View, Action: View>: View {
    public enum Jump: Sendable { case seen, any }

    @Binding var page: Int
    let count: Int
    /// Whether → may move past this page (a page that waits on something,
    /// a required grant, says no until it is done).
    let canAdvance: (Int) -> Bool
    let jump: Jump
    let marker: (Int) -> Color?
    @ViewBuilder let content: (Int) -> Content
    @ViewBuilder let action: (Int) -> Action

    @State private var seen = 0

    public init(
        page: Binding<Int>, count: Int, canAdvance: @escaping (Int) -> Bool = { _ in true },
        jump: Jump = .seen, marker: @escaping (Int) -> Color? = { _ in nil },
        @ViewBuilder content: @escaping (Int) -> Content,
        @ViewBuilder action: @escaping (Int) -> Action
    ) {
        precondition(count > 0, "InkPages needs at least one page")
        self._page = page
        self.count = count
        self.canAdvance = canAdvance
        self.jump = jump
        self.marker = marker
        self.content = content
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 0) {
            // A real pager: every page side by side in one row, the walk the
            // row's position. Moving is the row sliding to `page`, so the
            // direction is the geometry's, never a flag: whoever changes
            // `page` (Back, a dot, a swipe, the caller's "Continue"), the
            // pages move the right way. The pages not shown are disabled, so
            // their buttons and ⏎ cannot fire, and hidden from accessibility.
            GeometryReader { frame in
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        let here = index == page
                        content(index)
                            .padding(32)
                            .frame(width: frame.size.width, height: frame.size.height)
                            .opacity(here ? 1 : 0)
                            .disabled(!here)
                            .accessibilityHidden(!here)
                    }
                }
                .offset(x: -CGFloat(page) * frame.size.width)
                .animation(inkGlide, value: page)
            }
            .clipped()
            .contentShape(Rectangle())
            .modifier(
                Swipe { forward in
                    if forward { advance() } else { back() }
                })
            footer.padding(.horizontal, 20).padding(.vertical, 16)
        }
        .focusable()
        .focusEffectDisabled()
        // a watch has no keys: its crown and swipes walk the pages
        #if !os(watchOS)
            .onKeyPress(.leftArrow) {
                back()
                return .handled
            }
            .onKeyPress(.rightArrow) { advance() ? .handled : .ignored }
        #endif
        .onChange(of: page, initial: true) { _, now in seen = max(seen, now) }
    }

    private var footer: some View {
        ZStack {
            InkPageDots(
                count: count, current: page, marker: marker,
                reachable: { jump == .any || $0 <= seen }
            ) { go(to: $0) }
            // Back always in its place (disabled on the first page) and the
            // way on always in its: a pointer clicking through the walk
            // never lands on empty space.
            HStack {
                Button("Back") { back() }.buttonStyle(.ink).disabled(page == 0)
                Spacer()
                action(page)
            }
        }
    }

    private func back() {
        guard page > 0 else { return }
        go(to: page - 1)
    }

    /// Forward one page, unless this page waits on something.
    @discardableResult
    private func advance() -> Bool {
        guard page < count - 1, canAdvance(page) else { return false }
        go(to: page + 1)
        return true
    }

    /// A move from here; the row slides to it like any other change of `page`.
    private func go(to target: Int) {
        guard target != page, (0..<count).contains(target) else { return }
        page = target
    }
}

/// Pages follow the fingers: a horizontal swipe over the page walks one page
/// (fingers left, forward), once per gesture, as soon as it has clearly
/// travelled. A Mac's trackpad swipe is two-finger scrolling, which SwiftUI
/// offers no gesture for, so it is read from the scroll events over this view:
/// precise (a trackpad, never a wheel's clicks), more sideways than up,
/// momentum ignored, the person's natural-scrolling setting honoured. On a
/// touch screen, a drag; on a TV, the remote's swipe, which arrives as a move.
private struct Swipe: ViewModifier {
    let swiped: (_ forward: Bool) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
            content.background(SwipeReader(swiped: swiped))
        #elseif os(tvOS)
            content.onMoveCommand { direction in
                switch direction {
                case .left: swiped(false)
                case .right: swiped(true)
                default: break
                }
            }
        #else
            content.gesture(
                DragGesture(minimumDistance: 24).onEnded { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height),
                        abs(drag.translation.width) > 60
                    else { return }
                    swiped(drag.translation.width < 0)
                })
        #endif
    }
}

#if os(macOS)
    private struct SwipeReader: NSViewRepresentable {
        let swiped: (_ forward: Bool) -> Void

        func makeNSView(context: Context) -> Reader { Reader(swiped: swiped) }
        func updateNSView(_ view: Reader, context: Context) { view.swiped = swiped }

        /// Watches the window's scroll events (a local monitor: SwiftUI's
        /// views above take the hits) and keeps the ones over itself.
        final class Reader: NSView {
            var swiped: (_ forward: Bool) -> Void
            private var monitor: Any?
            /// Sideways travel of the fingers in this gesture, and whether it
            /// already walked.
            private var travel: CGFloat = 0
            private var walked = false
            /// How far the fingers move before it counts.
            private static let threshold: CGFloat = 50

            init(swiped: @escaping (_ forward: Bool) -> Void) {
                self.swiped = swiped
                super.init(frame: .zero)
            }

            required init?(coder: NSCoder) { preconditionFailure("not from a nib") }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                guard window != nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                    [weak self] event in
                    self?.read(event)
                    return event
                }
            }

            private func read(_ event: NSEvent) {
                guard event.window === window, event.hasPreciseScrollingDeltas,
                    event.momentumPhase.isEmpty,
                    bounds.contains(convert(event.locationInWindow, from: nil))
                else { return }
                if event.phase.contains(.began) {
                    travel = 0
                    walked = false
                }
                guard event.phase.contains(.changed), !walked,
                    abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                else { return }
                // The fingers' own direction, whatever natural scrolling does
                // to the content's.
                travel +=
                    event.isDirectionInvertedFromDevice
                    ? event.scrollingDeltaX : -event.scrollingDeltaX
                guard abs(travel) > Self.threshold else { return }
                walked = true
                swiped(travel < 0)
            }
        }
    }
#endif

/// The markers of a walk: a dot per page, the page here a short capsule,
/// gliding to the page chosen. A page with a `marker` colour wears it (its
/// state, read at a glance); the others the neutral ink, strong enough to
/// read on glass. A `reachable` dot is a click to its page and lifts under the
/// hand; another is only a marker, fainter.
public struct InkPageDots: View {
    let count: Int
    let current: Int
    let marker: (Int) -> Color?
    let reachable: (Int) -> Bool
    let jump: (Int) -> Void
    @Environment(\.inkMaterial) private var material
    @State private var hovered: Int?

    public init(
        count: Int, current: Int, marker: @escaping (Int) -> Color? = { _ in nil },
        reachable: @escaping (Int) -> Bool, jump: @escaping (Int) -> Void
    ) {
        self.count = count
        self.current = current
        self.marker = marker
        self.reachable = reachable
        self.jump = jump
    }

    public var body: some View {
        // Every dot owns the same slot: the page here draws wider INSIDE its
        // slot (into the spacing), so the row's layout never changes with the
        // page and no animation can leave a gap or shift a neighbour.
        HStack(spacing: 11) {
            ForEach(0..<count, id: \.self) { index in
                let here = index == current
                let open = reachable(index)
                Capsule()
                    .fill(colour(index, here: here, open: open))
                    .frame(width: here ? 17 : 7, height: 7)
                    .scaleEffect(hovered == index && open && !here ? 1.35 : 1)
                    .frame(width: 7, height: 7)
                    .contentShape(Rectangle().inset(by: -5))
                    .onTapGesture { if open { jump(index) } }
                    .inkHover(
                        Binding(
                            get: { hovered == index },
                            set: { hovered = $0 ? index : (hovered == index ? nil : hovered) })
                    )
                    .accessibilityLabel("page \(index + 1) of \(count)")
                    .accessibilityAddTraits(here ? .isSelected : [])
            }
        }
        .animation(inkGlide, value: current)
        .animation(.inkFlick, value: hovered)
        // On glass the markers ride a small glass capsule, one family with
        // the buttons beside them; flat, they stand bare. Room at the ends
        // for the page here drawn past its slot.
        .padding(.horizontal, 15).padding(.vertical, 9)
        .modifier(InkGlass(on: material == .glass, in: Capsule()))
    }

    private func colour(_ index: Int, here: Bool, open: Bool) -> Color {
        if let tint = marker(index) { return tint.opacity(here || open ? 1 : 0.5) }
        return .primary.opacity(here ? 0.95 : open ? 0.5 : 0.25)
    }
}
