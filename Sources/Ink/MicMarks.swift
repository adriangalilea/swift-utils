import SwiftUI

// The mic's marks, designed once for every surface that shows a mic (the ask
// prompt, a form that listens, vigil's dictation, the phone): plain values
// in, no audio and no settings knowledge. What the mic MEANS (its modes, who
// holds the talk key) is the senses' business; these only draw it.

/// A choice of a few named states as one capsule, the chosen one filled in
/// the accent: a mode switch that says which state it is in and is changed
/// with a click.
public struct InkSegments<Value: Hashable>: View {
    let values: [Value]
    let chosen: Value
    let label: (Value) -> String
    let size: CGFloat
    let choose: (Value) -> Void

    public init(
        _ values: [Value], chosen: Value, size: CGFloat = 11, label: @escaping (Value) -> String,
        choose: @escaping (Value) -> Void
    ) {
        self.values = values
        self.chosen = chosen
        self.label = label
        self.size = size
        self.choose = choose
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                let on = chosen == value
                Text(label(value))
                    .font(.system(size: size, weight: on ? .semibold : .regular))
                    .padding(.horizontal, size * 0.65).padding(.vertical, size * 0.2)
                    .background(
                        on ? AnyShapeStyle(Color.accentColor.opacity(0.85)) : AnyShapeStyle(.clear),
                        in: Capsule()
                    )
                    .foregroundStyle(on ? Color.white : Color.secondary)
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.spring(duration: 0.2)) { choose(value) } }
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(1.5)
        .background(.quaternary, in: Capsule())
        .fixedSize()
    }
}

/// Four bars lighting left to right with a 0-1 level: the mic breathing.
public struct InkMeter: View {
    let level: Double

    public init(level: Double) { self.level = level }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.primary.opacity(level * 4 > Double(i) + 0.5 ? 0.8 : 0.18))
                    .frame(width: 3, height: CGFloat(5 + i * 2))
            }
        }
        .animation(.linear(duration: 0.066), value: level)
    }
}

/// The AirPods mark tilting with the wearer's head (`angle`, degrees, + is a
/// nod down), so "is it reading my head" is answered by looking. nil angle:
/// the AirPods are the route but no motion arrives; drawn still and dim.
public struct InkHeadBadge: View {
    let angle: Double?
    let size: CGFloat

    public init(angle: Double?, size: CGFloat = 12) {
        self.angle = angle
        self.size = size
    }

    public var body: some View {
        Image(systemName: "airpods.pro")
            .font(.system(size: size))
            .rotationEffect(.degrees(-(angle ?? 0)))
            .opacity(angle == nil ? 0.45 : 1)
            .animation(.linear(duration: 0.066), value: angle ?? 0)
            .help(angle == nil ? "AirPods: no head motion" : "AirPods: reading your head")
    }
}
