import GitKit
import Ink
import SwiftUI

/// What a git surface says while it has nothing to show: reading, empty, or failed, in
/// the same calm voice everywhere (a symbol, a line, a quieter line, an action).
public struct GitStateView: View {
    public enum Phase {
        case loading(String)
        case empty(title: String, message: String?, symbol: String = "checkmark.circle")
        case failed(Error, retry: (@MainActor () -> Void)? = nil)
    }

    let phase: Phase

    public init(_ phase: Phase) { self.phase = phase }

    public var body: some View {
        VStack(spacing: .inkGap) {
            switch phase {
            case .loading(let title):
                ProgressView().controlSize(.small)
                Text(title).font(.callout).foregroundStyle(.secondary)
            case .empty(let title, let message, let symbol):
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
            case .failed(let error, let retry):
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.orange.opacity(0.8))
                Text("Couldn’t read this").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                Text(String(describing: error))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .lineLimit(6)
                if let retry {
                    Button("Try Again", action: retry).buttonStyle(.ink).padding(.top, .inkTight)
                }
            }
        }
        .padding(.inkBlock)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }
}
