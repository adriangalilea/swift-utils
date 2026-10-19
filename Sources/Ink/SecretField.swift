import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// What a secret field asks the system's AutoFill for, in each platform's own
/// type: `.password` fills one that exists, `.newPassword` offers to make a
/// strong one (1Password and the like take part as the system's provider).
#if os(macOS)
    public typealias SecretContentType = NSTextContentType
#else
    public typealias SecretContentType = UITextContentType
#endif

/// The one box a secret is typed into: SecretField wears it, and so does
/// Biometrics' field once a finger has authorized it, so the two cannot drift.
package struct SecretBox: ViewModifier {
    package let border: Color

    package init(border: Color) { self.border = border }

    package func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(border, lineWidth: 1))
            .animation(.snappy(duration: 0.15), value: border)
    }
}

/// A secret typed in: hidden as it is typed, an eye beside it to show it while
/// the person checks it. `valid` (nil: no judgement) borders it green or amber
/// once something is typed; `trailing` is the accessory slot after the eye
/// (Biometrics puts its sensor there). Accessories stay quiet, the text owns
/// the field (matched against 1Password's).
///
///     SecretField(prompt: "password", text: $password)
///     SecretField(prompt: "new password", text: $new, contentType: .newPassword, valid: new.count >= 12)
///
/// For a secret shown rather than typed (a serial, a key), `Veiled`; to copy one
/// without showing it, `Copy(value)` beside the `Veiled`.
public struct SecretField<Trailing: View>: View {
    let prompt: String
    @Binding var text: String
    var contentType: SecretContentType?
    var valid: Bool?
    @ViewBuilder var trailing: () -> Trailing
    @State private var visible = false

    public init(
        prompt: String, text: Binding<String>,
        contentType: SecretContentType? = .password, valid: Bool? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.prompt = prompt
        self._text = text
        self.contentType = contentType
        self.valid = valid
        self.trailing = trailing
    }

    private var border: Color {
        guard let valid, !text.isEmpty else { return .secondary.opacity(0.25) }
        return valid ? .green.opacity(0.8) : .orange.opacity(0.55)
    }

    public var body: some View {
        HStack(spacing: 6) {
            Group {
                if visible {
                    TextField(prompt, text: $text)
                } else {
                    SecureField(prompt, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .textContentType(contentType)
            if valid == true {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
            Button {
                visible.toggle()
            } label: {
                Image(systemName: visible ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(visible ? "hide" : "show", bundle: .module))
            .inkTip(visible ? "hide" : "show")
            trailing()
        }
        .modifier(SecretBox(border: border))
        .animation(.snappy(duration: 0.15), value: valid)
    }
}

extension SecretField where Trailing == EmptyView {
    public init(
        prompt: String, text: Binding<String>,
        contentType: SecretContentType? = .password, valid: Bool? = nil
    ) {
        self.init(
            prompt: prompt, text: text, contentType: contentType, valid: valid,
            trailing: { EmptyView() })
    }
}
