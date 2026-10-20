import SwiftUI

/// One tab of `InkTabs`: its words and the value it chooses.
public struct InkTab<Value: Hashable>: Identifiable {
    public let label: String
    public let value: Value
    public let disabled: Bool
    public var id: Value { value }

    public init(_ label: String, _ value: Value, disabled: Bool = false) {
        self.label = label
        self.value = value
        self.disabled = disabled
    }
}

/// Tabs, as ui's `tabs` draws them (one design on the web and here), in two looks:
/// `segment`, the tabs in a sunken well and the chosen one lifted out of it; `line`, a
/// rule under the tabs and the chosen one's stretch of it lit. Plain, or `glass`: the
/// well a bar of Liquid Glass and the lift a lit pane, the line glowing. The lift
/// glides to the tab chosen. Never the platform's segmented control, which paints the
/// chosen one in the accent: a choice among equals is not a yes.
public struct InkTabs<Value: Hashable>: View {
    public enum Look: Sendable { case segment, line }
    public enum Material: Sendable { case plain, glass }
    /// The list's height: 28, 32, 40 (a toolbar's, a field's, a heading's).
    public enum Size: Sendable { case small, medium, large }

    @Binding var selection: Value
    let tabs: [InkTab<Value>]
    let look: Look
    let material: Material
    let size: Size
    @Namespace private var lift

    public init(
        _ selection: Binding<Value>, _ tabs: [InkTab<Value>], look: Look = .segment,
        material: Material = .plain, size: Size = .medium
    ) {
        self._selection = selection
        self.tabs = tabs
        self.look = look
        self.material = material
        self.size = size
    }

    /// ui's glide: 300 ms, cubic-bezier(0.22, 1, 0.36, 1).
    static var glide: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: 0.3) }

    private var listHeight: CGFloat {
        switch size {
        case .small: 28
        case .medium: 32
        case .large: 40
        }
    }
    /// A segment's tab: the list's height less the well's padding.
    private var tabHeight: CGFloat { look == .segment ? listHeight - 4 : listHeight }
    private var inset: CGFloat {
        switch size {
        case .small: 10
        case .medium: 12
        case .large: 16
        }
    }
    private var fontSize: CGFloat {
        switch size {
        case .small: 12
        case .medium: 13
        case .large: 14
        }
    }

    public var body: some View {
        switch look {
        case .segment: segment
        case .line: line
        }
    }

    private var segment: some View {
        HStack(spacing: 2) { ForEach(tabs) { tab($0) } }
            .padding(2)
            .background { well }
    }

    @ViewBuilder private var well: some View {
        switch material {
        case .plain:
            RoundedRectangle(cornerRadius: .inkField, style: .continuous)
                .fill(.primary.opacity(0.06))
        case .glass:
            Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
        }
    }

    private var line: some View {
        HStack(spacing: 4) { ForEach(tabs) { tab($0) } }
            .background(alignment: .bottom) {
                Rectangle().fill(.primary.opacity(material == .glass ? 0.15 : 0.10))
                    .frame(height: 1)
            }
    }

    private func tab(_ t: InkTab<Value>) -> some View {
        let chosen = t.value == selection
        return Button {
            withAnimation(Self.glide) { selection = t.value }
        } label: {
            Text(t.label)
                .font(.system(size: fontSize, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, inset)
                .frame(height: tabHeight)
                .contentShape(Rectangle())
                .background { if chosen { liftShape } }
        }
        .buttonStyle(TabStyle(chosen: chosen))
        .disabled(t.disabled)
    }

    @ViewBuilder private var liftShape: some View {
        switch (look, material) {
        case (.segment, .plain):
            RoundedRectangle(cornerRadius: .inkRow, style: .continuous)
                .fill(.primary.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: .inkRow, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                .matchedGeometryEffect(id: "lift", in: lift)
        case (.segment, .glass):
            Capsule().fill(.primary.opacity(0.14))
                .glassEffect(.regular, in: Capsule())
                .matchedGeometryEffect(id: "lift", in: lift)
        case (.line, let m):
            VStack {
                Spacer(minLength: 0)
                Capsule().fill(.primary).frame(height: 2)
                    .shadow(color: m == .glass ? .primary.opacity(0.6) : .clear, radius: 4)
            }
            .matchedGeometryEffect(id: "lift", in: lift)
        }
    }

    /// The words: the primary ink faint at rest, nearer under the hand, whole when
    /// chosen; a disabled tab at half.
    private struct TabStyle: ButtonStyle {
        let chosen: Bool

        func makeBody(configuration: Configuration) -> some View {
            Styled(chosen: chosen, configuration: configuration)
        }

        private struct Styled: View {
            @Environment(\.isEnabled) private var enabled
            @State private var hovering = false
            let chosen: Bool
            let configuration: Configuration

            var body: some View {
                configuration.label
                    .foregroundStyle(.primary.opacity(chosen ? 1 : hovering ? 0.85 : 0.55))
                    .opacity(enabled ? 1 : 0.5)
                    .inkHover($hovering)
                    .animation(.inkFlick, value: hovering)
            }
        }
    }
}
