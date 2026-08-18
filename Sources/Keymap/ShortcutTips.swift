import SwiftUI

// MARK: - Floating shortcut tips (absolute, escape-clip, zero layout shift)

/// One accelerator for a command - a node in the chord trie. A command can
/// have several (bare `⌫`, `⌘⌫`, `⇧⌘⌫`), each surfacing under a different
/// held prefix. `isGlobal` marks the form that fires even when the app
/// isn't key.
public struct ShortcutChord: Sendable {
    public let modifiers: EventModifiers
    public let display: String
    public let isGlobal: Bool

    public init(modifiers: EventModifiers, display: String, isGlobal: Bool) {
        self.modifiers = modifiers
        self.display = display
        self.isGlobal = isGlobal
    }

    /// A media-key chord (⏮ ⏭ ⏯) - global (the OS routes it to the
    /// now-playing app), no modifiers, so it surfaces on the global layer.
    public static func mediaKey(_ glyph: String) -> ShortcutChord {
        ShortcutChord(modifiers: [], display: glyph, isGlobal: true)
    }
}

extension EventModifiers {
    fileprivate var count: Int { rawValue.nonzeroBitCount }
}

/// THE which-key rule: completions of the held prefix, filtered by
/// reachability. The focused layers (a held modifier, the bare reveal) show
/// just the one best completion; the global reference shows EVERY way to
/// reach it (⏯ and ⇧⌘Space both), so you pick whatever's comfortable.
/// Empty = nothing reachable from here.
public func shortcutCompletions(_ chords: [ShortcutChord], _ reveal: RevealMonitor.Reveal)
    -> [String]
{
    let matching =
        chords
        .filter {
            $0.modifiers.isSuperset(of: reveal.required) && (!reveal.globalsOnly || $0.isGlobal)
        }
        .sorted {
            ($0.modifiers.count, $0.isGlobal ? 1 : 0) < ($1.modifiers.count, $1.isGlobal ? 1 : 0)
        }
    guard !matching.isEmpty else { return [] }
    let chosen = reveal.globalsOnly ? matching : [matching[0]]
    var seen = Set<String>()
    return chosen.compactMap { seen.insert($0.display).inserted ? $0.display : nil }
}

/// A control's request to float its chord(s) over itself while a reveal is
/// on. The control contributes an anchor; ONE layer at the window root reads
/// them all - so the tips overflow bounds (toolbar, list rows, glass) and
/// never push a pixel of layout. One item per command; a row carries several
/// labeled ones.
public struct ShortcutTip: Identifiable {
    public let id: String
    public let anchor: Anchor<CGRect>
    public let edge: Edge
    public let items: [Item]

    public struct Item {
        public let chords: [ShortcutChord]
        public let label: LocalizedStringKey?
        public init(chords: [ShortcutChord], label: LocalizedStringKey? = nil) {
            self.chords = chords
            self.label = label
        }
    }
}

public struct ShortcutTipKey: PreferenceKey {
    public static var defaultValue: [ShortcutTip] { [] }
    public static func reduce(value: inout [ShortcutTip], nextValue: () -> [ShortcutTip]) {
        value.append(contentsOf: nextValue())
    }
}

/// The tip itself: a glass capsule legible over bright video. Each item
/// shows the minimal completion of the current prefix; items with no
/// completion drop out, and an all-empty tip renders nothing.
public struct ShortcutTipView: View {
    let items: [ShortcutTip.Item]
    let reveal: RevealMonitor.Reveal

    public init(items: [ShortcutTip.Item], reveal: RevealMonitor.Reveal) {
        self.items = items
        self.reveal = reveal
    }

    private var shown: [(keys: [String], label: LocalizedStringKey?)] {
        items.compactMap { item in
            let keys = shortcutCompletions(item.chords, reveal)
            return keys.isEmpty ? nil : (keys, item.label)
        }
    }

    public var body: some View {
        if !shown.isEmpty {
            HStack(spacing: 9) {
                ForEach(shown.indices, id: \.self) { index in
                    HStack(spacing: 4) {
                        // Multiple ways to reach it (⏯ / ⇧⌘Space) stack so
                        // you read both at a glance, not a cramped inline list.
                        VStack(spacing: 1) {
                            ForEach(shown[index].keys, id: \.self) { key in
                                Text(key).font(.caption2.monospaced().weight(.semibold))
                            }
                        }
                        if let label = shown[index].label {
                            Text(label).font(.caption2.weight(.medium)).foregroundStyle(
                                .white.opacity(0.72))
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: Capsule())
            .environment(\.colorScheme, .dark)
            .fixedSize()
        }
    }
}

/// Drawn once at the window root - observes the monitor itself, so it (and
/// the preference closure) re-render the instant a reveal turns on.
private struct ShortcutTipLayer: ViewModifier {
    @Environment(RevealMonitor.self) private var monitor

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(ShortcutTipKey.self) { tips in
            GeometryReader { proxy in
                if let reveal = monitor.reveal {
                    ForEach(tips) { tip in
                        PlacedTip(
                            items: tip.items, reveal: reveal,
                            anchor: proxy[tip.anchor], edge: tip.edge, bounds: proxy.size)
                    }
                }
            }
            .allowsHitTesting(false)
            .animation(.inkFlick, value: monitor.revealing)
        }
    }
}

extension View {
    /// Float a registry command's chords over this control. The layer picks
    /// the right one for whatever prefix is held. `extra` adds non-registry
    /// chords - e.g. the media-key glyphs (⏮ ⏭ ⏯).
    public func shortcutTip<A: ActionSet>(
        _ action: A, _ store: KeymapStore<A>,
        extra: [ShortcutChord] = [], edge: Edge = .top
    ) -> some View {
        let item = ShortcutTip.Item(chords: store.chords(for: action) + extra, label: nil)
        return anchorPreference(key: ShortcutTipKey.self, value: .bounds) {
            [ShortcutTip(id: action.rawValue, anchor: $0, edge: edge, items: [item])]
        }
    }

    /// Float a row of labeled actions. Only contributes while `present`
    /// (the selected row).
    public func shortcutActions(
        _ id: String, _ items: [ShortcutTip.Item], present: Bool, edge: Edge = .top
    ) -> some View {
        anchorPreference(key: ShortcutTipKey.self, value: .bounds) {
            present ? [ShortcutTip(id: id, anchor: $0, edge: edge, items: items)] : []
        }
    }

    /// Install once at the window root: collects every tip anchor and
    /// renders the floating layer while a reveal is on. Drawn above
    /// everything, hit-testing off, so it overflows freely and shifts
    /// nothing. Requires a `RevealMonitor` in the environment.
    public func shortcutTipLayer() -> some View { modifier(ShortcutTipLayer()) }
}

/// One floating tip, kept on screen. A wide row capsule centered on a
/// narrow row would clip off the window's edge, so its horizontal position
/// clamps to keep the LEFT edge in view and let any overflow run right,
/// into the open detail area (where the hit-test-free layer draws above
/// everything).
private struct PlacedTip: View {
    let items: [ShortcutTip.Item]
    let reveal: RevealMonitor.Reveal
    let anchor: CGRect
    let edge: Edge
    let bounds: CGSize
    @State private var size: CGSize = .zero

    var body: some View {
        ShortcutTipView(items: items, reveal: reveal)
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { size = $0 }
            .position(point)
    }

    private var point: CGPoint {
        let gap: CGFloat = 14
        switch edge {
        case .top: return CGPoint(x: clampedX, y: anchor.minY - gap)
        case .bottom: return CGPoint(x: clampedX, y: anchor.maxY + gap)
        case .leading: return CGPoint(x: anchor.minX - gap, y: anchor.midY)
        case .trailing: return CGPoint(x: anchor.maxX + gap, y: anchor.midY)
        }
    }

    /// Center-x that keeps the capsule visible: the left edge never crosses
    /// the margin; the right edge stays in bounds when it fits, otherwise it
    /// spills right rather than off the left.
    private var clampedX: CGFloat {
        let half = size.width / 2
        let lo = half + 8
        let hi = max(lo, bounds.width - half - 8)
        return min(max(anchor.midX, lo), hi)
    }
}
