import Keymap
import SwiftUI

/// The overlay's face: the frontmost app's keymap as a dark glass card,
/// sections in flowing columns, one row per action (title left, keycaps
/// right, globe on the system-wide forms), tinted with the app's accent.
/// Apps that publish no manifest get a quiet one-liner, not an error.
struct OverlayView: View {
    let manifest: KeymapManifest?
    let appName: String

    private var accent: Color {
        guard let manifest else { return .secondary }
        return Color(hex: manifest.accent) ?? .secondary
    }

    var body: some View {
        Group {
            if let manifest {
                card(manifest)
            } else {
                Text("\(appName) publishes no keymap")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(24)
            }
        }
        .background(.black.opacity(0.55))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
    }

    private func card(_ manifest: KeymapManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(manifest.appName)
                    .font(.headline)
                Spacer(minLength: 24)
                Text("⌃⌘/ to dismiss")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            // Columns of sections, wrapped by hand: tall sections first would
            // balance better, but source order preserves each app's intent.
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
            Text(section.name.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
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
                        keycap(combo)
                    }
                    if let combo = action.global.first {
                        HStack(spacing: 3) {
                            Image(systemName: "globe")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            keycap(combo)
                        }
                    }
                }
                .frame(width: 250)
            }
        }
    }

    private func keycap(_ combo: String) -> some View {
        Text(combo)
            .font(.callout.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }

    /// Greedy column fill: sections stack into a column until it holds
    /// `per` action rows, then a new column starts.
    private func columned(_ sections: [KeymapManifest.Section], per: Int) -> [[KeymapManifest.Section]] {
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

extension Color {
    /// "#RRGGBB" → Color; nil on anything else.
    init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 7,
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
