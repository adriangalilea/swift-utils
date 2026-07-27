import AppKit
import Ink
import SwiftUI

/// The colophon - the book trade's word for the page that names who made a
/// thing, how, and where it lives. One grouped Form every studio app drops
/// into its Settings as the about/support tab, so the "made by" surface is
/// designed ONCE and can never drift between apps.
///
/// Identity derives from the RUNNING BUNDLE (name, version, build, icon) -
/// the one source that cannot lie about what's installed. Only what a
/// bundle can't know arrives as data: the author, the links, the support
/// ask, and an optional updates hook (Sparkle stays app-side; this takes a
/// closure).
public struct ColophonLink: Identifiable, Sendable {
    public let title: String
    public let symbol: String
    public let url: URL
    public var id: String { title }

    public init(_ title: String, symbol: String, url: URL) {
        self.title = title
        self.symbol = symbol
        self.url = url
    }
}

public struct ColophonPane: View {
    let author: ColophonLink
    let links: [ColophonLink]
    let support: [ColophonLink]
    let ask: String?
    let checkForUpdates: (() -> Void)?

    /// `ask` is the one sentence above the support links, in the APP's
    /// voice - pass it localized from the app. nil drops the sentence,
    /// empty `support` drops the whole section.
    public init(
        author: ColophonLink,
        links: [ColophonLink] = [],
        support: [ColophonLink] = [],
        ask: String? = nil,
        checkForUpdates: (() -> Void)? = nil
    ) {
        self.author = author
        self.links = links
        self.support = support
        self.ask = ask
        self.checkForUpdates = checkForUpdates
    }

    public var body: some View {
        Form {
            Section {
                identity
            }
            if !links.isEmpty {
                Section {
                    ForEach(links, content: row)
                }
            }
            if !support.isEmpty {
                Section {
                    ForEach(support, content: row)
                } footer: {
                    if let ask {
                        Text(ask)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var identity: some View {
        HStack(spacing: .inkLane) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.appName)
                    .font(.title3.weight(.semibold))
                Text(verbatim: "\(Self.version) (\(Self.build))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Link(destination: author.url) {
                    Text(String(localized: "made by \(author.title)", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .underline()
                }
            }
            Spacer()
            if let checkForUpdates {
                Button(String(localized: "Check for Updates…", bundle: .module), action: checkForUpdates)
            }
        }
        .padding(.vertical, .inkTight)
    }

    /// A link as a full-width form row: neutral foreground (never browser
    /// blue in a Form), the ↗ naming it as leaving the app.
    private func row(_ link: ColophonLink) -> some View {
        Link(destination: link.url) {
            HStack(spacing: .inkGap) {
                Label(link.title, systemImage: link.symbol)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Bundle identity (the source that can't lie)

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
