import AppKit
import Ink
import SwiftUI

/// The colophon - the book trade's word for the page that names who made a
/// thing, how, and where it lives. Designed ONCE at the standard the first
/// consumer set: labeled rows whose values are link clusters, the warm
/// support card (the one golden moment in Settings), and the honest
/// footnotes. Two hosts ship it: `ColophonPane` is a complete Settings tab
/// (identity header + the sections); `ColophonSections` embeds the same
/// sections inside an app's own grouped Form.
///
/// Identity derives from the RUNNING BUNDLE (name, version, build, icon) -
/// the one source that cannot lie about what's installed. Everything a
/// bundle can't know arrives as data.
public struct ColophonLink: Identifiable, Sendable {
    public let title: String
    public let symbol: String
    public let url: URL
    public var id: String { title }

    public init(_ title: String, symbol: String = "", url: URL) {
        self.title = title
        self.symbol = symbol
        self.url = url
    }
}

/// One labeled row whose value is a cluster of text links ("Telegram · Email").
public struct ColophonRow: Identifiable, Sendable {
    public let label: String
    public let links: [ColophonLink]
    public var id: String { label }

    public init(_ label: String, _ links: [ColophonLink]) {
        self.label = label
        self.links = links
    }
}

/// The support card's content. The tint defaults to the studio gold -
/// support warmth is its own color, not the app accent.
public struct ColophonSupport: Sendable {
    public let title: String
    public let message: String
    public let links: [ColophonLink]
    public let tint: Color

    /// nil `title` = the localized "Support the developer".
    public init(
        title: String? = nil,
        message: String,
        links: [ColophonLink],
        tint: Color = .colophonGold
    ) {
        self.title = title ?? String(localized: "Support the developer", bundle: .module)
        self.message = message
        self.links = links
        self.tint = tint
    }
}

extension Color {
    /// The support-card gold, one value across every app.
    public static let colophonGold = Color(red: 0.93, green: 0.72, blue: 0.25)
}

// MARK: - The two hosts

/// A complete Settings tab: identity header (icon, name, version, byline,
/// the updates hook) + the shared sections.
public struct ColophonPane: View {
    let author: ColophonLink
    let rows: [ColophonRow]
    let support: ColophonSupport?
    let footnotes: [String]
    let checkForUpdates: (() -> Void)?

    public init(
        author: ColophonLink,
        rows: [ColophonRow] = [],
        support: ColophonSupport? = nil,
        footnotes: [String] = [],
        checkForUpdates: (() -> Void)? = nil
    ) {
        self.author = author
        self.rows = rows
        self.support = support
        self.footnotes = footnotes
        self.checkForUpdates = checkForUpdates
    }

    public var body: some View {
        Form {
            Section {
                identity
            }
            Section {
                ForEach(rows, content: rowView)
                if let support {
                    SupportCard(support: support)
                }
            } footer: {
                footnoteText(footnotes)
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
                Text(Bundle.colophonName)
                    .font(.title3.weight(.semibold))
                Text(verbatim: "\(Bundle.colophonVersion) (\(Bundle.colophonBuild))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Link(String(localized: "made by \(author.title)", bundle: .module), destination: author.url)
                    .font(.caption)
            }
            Spacer()
            if let checkForUpdates {
                Button(String(localized: "Check for Updates…", bundle: .module), action: checkForUpdates)
            }
        }
        .padding(.vertical, .inkTight)
    }
}

/// The same sections, embeddable inside an app's own grouped Form - for
/// apps whose About lives in an existing tab. `extras` renders FIRST in the
/// section (an app's live stat rows - "Time saved" - stay app-side views).
public struct ColophonSections<Extras: View>: View {
    let rows: [ColophonRow]
    let support: ColophonSupport?
    let footnotes: [String]
    let extras: Extras

    public init(
        rows: [ColophonRow] = [],
        support: ColophonSupport? = nil,
        footnotes: [String] = [],
        @ViewBuilder extras: () -> Extras = { EmptyView() }
    ) {
        self.rows = rows
        self.support = support
        self.footnotes = footnotes
        self.extras = extras()
    }

    public var body: some View {
        Section {
            extras
            LabeledContent(String(localized: "Version", bundle: .module),
                           value: "\(Bundle.colophonVersion) (\(Bundle.colophonBuild))")
            ForEach(rows, content: rowView)
            if let support {
                SupportCard(support: support)
            }
        } header: {
            Text(String(localized: "About", bundle: .module))
        } footer: {
            footnoteText(footnotes)
        }
    }
}

// MARK: - The shared pieces

/// A labeled row: the value is its links, joined by the quiet ·.
@ViewBuilder
private func rowView(_ row: ColophonRow) -> some View {
    LabeledContent(row.label) {
        HStack(spacing: 6) {
            ForEach(Array(row.links.enumerated()), id: \.offset) { index, link in
                if index > 0 { Text(verbatim: "·").foregroundStyle(.secondary) }
                Link(link.title, destination: link.url)
            }
        }
    }
}

@ViewBuilder
private func footnoteText(_ footnotes: [String]) -> some View {
    if !footnotes.isEmpty {
        VStack(alignment: .leading, spacing: .inkGap) {
            ForEach(footnotes, id: \.self) { Text($0) }
        }
    }
}

/// The one warm, golden moment in Settings. System rendering throughout:
/// glassProminent capsules, gradient color rendering on the heart.
/// NO symbolEffect, ever: on macOS 26.5 any repeating effect keeps the
/// window's AttributeGraph invalidating continuously (~23% app CPU +
/// WindowServer churn while visually idle, bisected on the first
/// consumer); one-shot effects measured clean but the heart stays static
/// anyway.
private struct SupportCard: View {
    let support: ColophonSupport

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "heart.fill")
                .font(.system(size: 26))
                .foregroundStyle(support.tint)
                .symbolColorRenderingMode(.gradient)
                .padding(.top, 2)
            Text(support.title)
                .font(.headline)
            Text(support.message)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            HStack(spacing: 10) {
                ForEach(support.links) { link in
                    Link(destination: link.url) {
                        Label(link.title, systemImage: link.symbol)
                    }
                }
            }
            .buttonStyle(.glassProminent)
            .tint(support.tint)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .inkBlock)
        .background(RoundedRectangle(cornerRadius: .inkLane).fill(LinearGradient(
            colors: [support.tint.opacity(0.14), support.tint.opacity(0.04)],
            startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: .inkLane).strokeBorder(LinearGradient(
            colors: [support.tint.opacity(0.4), support.tint.opacity(0.1)],
            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }
}

// MARK: - Bundle identity (the source that can't lie)

extension Bundle {
    fileprivate static var colophonName: String {
        main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
    }

    fileprivate static var colophonVersion: String {
        main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    fileprivate static var colophonBuild: String {
        main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
