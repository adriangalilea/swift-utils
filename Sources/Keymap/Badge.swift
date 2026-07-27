import SwiftUI

/// The one key-cap. Every surface renders combos through it - never
/// re-styled per site.
public struct ShortcutBadge: View {
    let text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// When a control shows its key. This is the SIMPLE discoverability tier -
/// one badge overlaid on one control; the anchored floating-tip layer
/// (ShortcutTips.swift) is the rich tier and the better default for dense
/// UI. Both read the same RevealMonitor, so the layers never disagree.
public enum BadgePolicy: Sendable {
    /// Only while the reveal layer is up (a held modifier prefix, or the
    /// bare-key reveal). The default: quiet until asked.
    case onReveal
    /// Permanently rendered beside the control - the "linear UI" mode.
    case always
}

extension View {
    /// Paints the action's key-cap on this control, driven by the ONE
    /// reveal monitor: under `.onReveal` the badge appears the instant the
    /// held prefix (or bare reveal) matches one of the action's combos,
    /// everywhere at once.
    public func keymapBadge<A: ActionSet>(
        _ action: A,
        store: KeymapStore<A>,
        monitor: RevealMonitor,
        policy: BadgePolicy = .onReveal,
        alignment: Alignment = .topTrailing
    ) -> some View {
        overlay(alignment: alignment) {
            if let text = badgeText(action, store: store, monitor: monitor, policy: policy) {
                ShortcutBadge(text)
            }
        }
    }
}

@MainActor private func badgeText<A: ActionSet>(
    _ action: A, store: KeymapStore<A>, monitor: RevealMonitor, policy: BadgePolicy
) -> String? {
    switch policy {
    case .always:
        let text = store.displayPrimary(for: action)
        return text.isEmpty ? nil : text
    case .onReveal:
        guard let reveal = monitor.reveal else { return nil }
        let combos = reveal.globalsOnly
            ? store.combos(for: action, .global)
            : store.combos(for: action, .local)
        return combos.first(where: monitor.completes)?.display
    }
}
