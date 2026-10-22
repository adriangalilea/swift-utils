import SwiftUI

// Time that runs out, drawn as something draining, never only as words.
// Two shapes of one idea: the EDGE, a line along a container's bottom that
// empties as the deadline nears (the time leaving the card itself), and
// the RING, its compact sibling for where there is no card (a toolbar, a
// Dynamic Island). Both ride the system's own timer progress
// (`ProgressView(timerInterval:)`): no timer of the host's, and they run
// where no app code runs (a widget, a Live Activity) exactly as in the app.
// The last stretch turns `warning`, redrawn at that moment where views
// redraw (an app); a widget keeps its tint and its host's stale date takes
// over at the deadline.

/// How a deadline is drawn: when it began, when it ends, and the colours of
/// time left and of time nearly gone.
public struct Deadline: Sendable, Hashable {
    public let from: Date
    public let until: Date
    /// The stretch before `until` drawn as nearly gone.
    public let last: TimeInterval

    public init(from: Date, until: Date, last: TimeInterval = 60) {
        precondition(from <= until, "a deadline ends after it begins")
        self.from = from
        self.until = until
        self.last = last
    }

    /// Nearly gone, from here on.
    var turns: Date { max(from, until.addingTimeInterval(-last)) }
}

/// The edge: a line along the bottom of the container it is laid on, full
/// when the deadline began, empty when it ends. Put it on a card with
/// `.deadlineEdge(_:in:)`, which lays it on the card's own shape.
public struct DeadlineEdge: View {
    let deadline: Deadline
    let tint: Color
    let warning: Color

    public init(_ deadline: Deadline, tint: Color = .accentColor, warning: Color = .orange) {
        self.deadline = deadline
        self.tint = tint
        self.warning = warning
    }

    public var body: some View {
        // Redrawn when the last stretch begins (an app; a widget draws once).
        TimelineView(.explicit([Date(), deadline.turns])) { context in
            ProgressView(timerInterval: deadline.from...deadline.until, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(context.date >= deadline.turns ? warning : tint)
            .labelsHidden()
        }
        .accessibilityHidden(true)
    }
}

/// The ring: the same time as a circle that empties, with an optional
/// symbol inside it.
public struct DeadlineRing: View {
    let deadline: Deadline
    let symbol: String?
    let tint: Color
    let warning: Color

    public init(
        _ deadline: Deadline, symbol: String? = nil, tint: Color = .primary,
        warning: Color = .orange
    ) {
        self.deadline = deadline
        self.symbol = symbol
        self.tint = tint
        self.warning = warning
    }

    /// A circular timer ProgressView is a ring only where WidgetKit draws it
    /// (a widget, a Live Activity); in an app it is the activity spinner.
    /// So in an app the ring draws itself, and in an extension the system does.
    static let drawnBySystem = Bundle.main.bundleURL.pathExtension == "appex"

    public var body: some View {
        Group {
            if Self.drawnBySystem {
                TimelineView(.explicit([Date(), deadline.turns])) { context in
                    ProgressView(timerInterval: deadline.from...deadline.until, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        if let symbol { Image(systemName: symbol).imageScale(.small) }
                    }
                    .progressViewStyle(.circular)
                    .tint(context.date >= deadline.turns ? warning : tint)
                }
            } else {
                // Four redraws a second: a ring a few points wide moves less
                // than a pixel between them.
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let total = max(0.001, deadline.until.timeIntervalSince(deadline.from))
                    let left = max(0, deadline.until.timeIntervalSince(context.date))
                    let ink = context.date >= deadline.turns ? warning : tint
                    ZStack {
                        Circle().stroke(ink.opacity(0.2), lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: left / total)
                            .stroke(ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        if let symbol {
                            Image(systemName: symbol).imageScale(.small).foregroundStyle(ink)
                        }
                    }
                    .padding(1.25)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Lays a `DeadlineEdge` along this view's bottom, inside `shape` (the
    /// card's own outline, so the line follows its corners).
    public func deadlineEdge<S: Shape>(
        _ deadline: Deadline?, in shape: S, tint: Color = .accentColor, warning: Color = .orange
    ) -> some View {
        overlay(alignment: .bottom) {
            if let deadline {
                DeadlineEdge(deadline, tint: tint, warning: warning)
            }
        }
        .clipShape(shape)
    }
}
