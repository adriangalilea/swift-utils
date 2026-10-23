import GitKit
import GitViews
import MarkdownText
import SwiftUI

#if os(macOS)
    import GitLocal
#endif

// Launch arguments, for a screenshot or a demo:
//   -repo PATH        the repository on a Mac (default ~/Developer/vigil)
//   -panel NAME       agent, working, commits, repo, embeds
//   -open N           open the panel's Nth row (0 the first); "all" every file; "submodule"
//   -embed NAME       markdown, cards, page (with -panel embeds)
//   -appearance NAME  light or dark

@main
struct GitViewerApp: App {
    var body: some Scene {
        WindowGroup {
            Viewer()
        }
        #if os(macOS)
            .defaultSize(width: 1360, height: 860)
        #endif
    }
}

/// The host: picks the source (a repository on this Mac, the bundled capture on a phone),
/// owns what a quote does (a sheet standing in for "send to agent") and the reload, and
/// adds the embeddings as a panel of its own.
struct Viewer: View {
    #if os(macOS)
        @State private var repository = URL(
            filePath: NSString(string: UserDefaults.standard.string(forKey: "repo") ?? "~/Developer/vigil")
                .expandingTildeInPath)
        @State private var picking = false
    #endif
    @State private var reload = 0
    @State private var quote: QuoteItem?

    var body: some View {
        browser
            .onQuote { quote = QuoteItem(quote: $0) }
            .sheet(item: $quote) { QuoteSheet(item: $0) }
            .preferredColorScheme(Launch.appearance)
            #if os(macOS)
                .id(repository)
                .toolbar {
                    ToolbarItem {
                        Button("Open Repository…", systemImage: "folder") { picking = true }
                    }
                    ToolbarItem {
                        Button("Reload", systemImage: "arrow.clockwise") { reload += 1 }
                    }
                }
                .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                    if case .success(let folder) = result { repository = folder }
                }
            #endif
    }

    var browser: GitBrowser {
        #if os(macOS)
            // A live repository has no agent on record: its session is simulated as the
            // last three commits and whatever is on disk since.
            let source = Git.LocalSource(repository: repository)
            let agent = GitBrowser.Agent(base: "HEAD~3", name: "Agent")
        #else
            let source = try! Git.FixtureSource(folder: Bundle.main.url(forResource: "scenario", withExtension: nil)!)
            let agent = source.manifest.agent.map { GitBrowser.Agent(base: $0.base, touched: $0.touched, name: "Agent") }
        #endif
        return GitBrowser(source: source, agent: agent, opening: Launch.opening, reloadToken: reload)
            .panel("Embeds", systemImage: "rectangle.on.rectangle.angled") { Embeds() }
    }
}

enum Launch {
    static var defaults: UserDefaults { .standard }

    static var opening: GitBrowser.Opening? {
        let panel: GitBrowser.Panel? =
            switch defaults.string(forKey: "panel") {
            case "agent": .agent
            case "working": .workingTree
            case "commits": .commits
            case "repo": .repository
            case "embeds": .extra(0)
            default: nil
            }
        guard let panel else { return nil }
        let row: GitBrowser.Opening.Row? =
            switch defaults.string(forKey: "open") {
            case nil: nil
            case "all": .allFiles
            case "submodule": .submodule
            case let index?: Int(index).map { .index($0) }
            }
        return GitBrowser.Opening(panel, row: row)
    }

    static var embed: Embed? { Embed(rawValue: defaults.string(forKey: "embed") ?? "") }

    static var appearance: ColorScheme? {
        switch defaults.string(forKey: "appearance") {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

enum Embed: String, Hashable, CaseIterable {
    case markdown, cards, page

    var title: String {
        switch self {
        case .markdown: "In a markdown answer"
        case .cards: "In a tool call's card"
        case .page: "Full screen, 10,000 lines"
        }
    }

    var symbol: String {
        switch self {
        case .markdown: "text.bubble"
        case .cards: "rectangle.stack"
        case .page: "rectangle.portrait"
        }
    }
}

/// The example's own panel: `DiffView` in the three places a host puts it.
struct Embeds: View {
    @State private var path: [Embed] = Launch.embed.map { [$0] } ?? []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(Embed.allCases, id: \.self) { embed in
                        NavigationLink(value: embed) { Label(embed.title, systemImage: embed.symbol) }
                    }
                } footer: {
                    Text(
                        "DiffView is one line anywhere: a fence in a markdown answer, a card in a conversation, a whole screen."
                    )
                }
            }
            .navigationTitle("Embeds")
            .navigationDestination(for: Embed.self) { EmbedDetail(embed: $0) }
        }
    }
}

struct QuoteItem: Identifiable {
    let quote: DiffQuote
    let id = UUID()
}

/// The quote a reader made, as an agent would receive it: the Markdown, drawn and as text.
struct QuoteSheet: View {
    let item: QuoteItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Send to the agent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    MarkdownView(item.quote.markdown)
                    Text("Markdown").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(verbatim: item.quote.markdown)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(20)
            }
            .navigationTitle(item.quote.reference)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") {
                        #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.quote.markdown, forType: .string)
                        #else
                            UIPasteboard.general.string = item.quote.markdown
                        #endif
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 560, minHeight: 480)
        #endif
    }
}
