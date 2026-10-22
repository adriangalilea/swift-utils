import MarkdownText
import SwiftUI

#if os(macOS)
    import AppKit

    // The markdown fixtures in a window: `swift run markdown-example`. A list of the
    // fixtures (real agent answers and the edge cases, `Tests/MarkdownTextTests/Fixtures`)
    // with each one's three-line preview; the chosen one drawn as a page, its footnote
    // variant under it. A `.streaming.md` fixture is drawn as text still arriving.

    let folder = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Tests/MarkdownTextTests/Fixtures")

    struct Fixture: Identifiable, Hashable {
        let id: String
        let text: String
        let streaming: Bool
    }

    let fixtures: [Fixture] = try! FileManager.default
        .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "md" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { url in
            let name = url.deletingPathExtension().lastPathComponent
            return Fixture(
                id: name, text: try! String(contentsOf: url, encoding: .utf8),
                streaming: name.hasSuffix(".streaming"))
        }

    struct DemoView: View {
        @State private var chosen: Fixture? = fixtures.first

        var body: some View {
            NavigationSplitView {
                List(fixtures, selection: $chosen) { fixture in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fixture.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        MarkdownView(fixture.text, streaming: fixture.streaming)
                            .markdownStyle(.footnote.preview(lines: 3))
                    }
                    .tag(fixture)
                    .padding(.vertical, 4)
                }
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
            } detail: {
                if let chosen {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            MarkdownView(chosen.text, streaming: chosen.streaming)
                            Divider()
                            MarkdownView(chosen.text, streaming: chosen.streaming)
                                .markdownStyle(.footnote)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 640)
        }
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
        styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
        backing: .buffered, defer: false)
    window.title = "MarkdownText"
    window.contentView = NSHostingView(rootView: DemoView())
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate()
    app.run()
#endif
