import Ink
import SwiftUI

extension KeymapManifest {
    /// The manifest's accent as a Color; nil when the hex is malformed.
    public var accentColor: Color? {
        guard accent.hasPrefix("#"), accent.count == 7,
            let value = UInt32(accent.dropFirst(), radix: 16)
        else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// A published keymap rendered as a card: sections in flowing columns, one
/// row per action (title left, keycaps right, globe on the system-wide
/// forms), tinted with the app's accent. Lives in the LIBRARY - the overlay
/// agent merely windows it, and any surface that wants to show another
/// app's keys renders the same card, on the same Ink.
public struct KeymapCard: View {
    let manifest: KeymapManifest
    /// The dismissal hint trailing the header ("⌃⌘/ to dismiss"), host-owned.
    let hint: String?

    public init(manifest: KeymapManifest, hint: String? = nil) {
        self.manifest = manifest
        self.hint = hint
    }

    private var accent: Color { manifest.accentColor ?? .secondary }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(manifest.appName)
                    .font(.headline)
                Spacer(minLength: 24)
                if let hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            // Columns of sections, wrapped greedily; source order preserves
            // each app's intent.
            let columns = columned(manifest.sections, per: 14)
            HStack(alignment: .top, spacing: 28) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(column.enumerated()), id: \.offset) { _, section in
                            sectionView(section)
                        }
                    }
                }
            }
        }
        .padding(22)
        .fixedSize()
    }

    private func sectionView(_ section: KeymapManifest.Section) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.name)
                .planeHeaderStyle(accent)
            ForEach(Array(section.actions.enumerated()), id: \.offset) { _, action in
                HStack(spacing: 12) {
                    Image(systemName: action.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(action.title)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let combo = action.local.first {
                        ShortcutBadge(combo)
                    }
                    if let combo = action.global.first {
                        HStack(spacing: 3) {
                            Image(systemName: "globe")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            ShortcutBadge(combo)
                        }
                    }
                }
                .frame(width: 250)
            }
        }
    }

    /// Greedy column fill: sections stack into a column until it holds
    /// `per` action rows, then a new column starts.
    private func columned(_ sections: [KeymapManifest.Section], per: Int) -> [[KeymapManifest
        .Section]]
    {
        var columns: [[KeymapManifest.Section]] = [[]]
        var rows = 0
        for section in sections {
            if rows >= per, !columns[columns.count - 1].isEmpty {
                columns.append([])
                rows = 0
            }
            columns[columns.count - 1].append(section)
            rows += section.actions.count + 1
        }
        return columns
    }
}
