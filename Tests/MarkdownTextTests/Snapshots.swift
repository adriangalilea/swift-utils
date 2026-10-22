import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import MarkdownText

/// The fixtures: real agent answers (their shape kept, nothing private in them) and
/// the edge cases. A name ending `.streaming.md` is a text cut mid-stream.
enum Fixtures {
    static let folder = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!

    static var all: [(name: String, text: String, streaming: Bool)] {
        let files = try! FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "md" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        assert(!files.isEmpty, "no fixtures in \(folder.path)")
        return files.map { url in
            let name = url.deletingPathExtension().lastPathComponent
            return (
                name.replacingOccurrences(of: ".streaming", with: ""),
                try! String(contentsOf: url, encoding: .utf8), name.hasSuffix(".streaming")
            )
        }
    }
}

struct FixtureTests {
    /// Every fixture parses to something, whole or cut.
    @Test func everyFixtureParses() {
        for fixture in Fixtures.all {
            let doc = MarkdownDocument(fixture.text, streaming: fixture.streaming)
            #expect(!doc.blocks.isEmpty, "\(fixture.name) parsed to nothing")
        }
    }
}

/// Each fixture drawn light and dark at this platform's widths, as PNGs into the folder
/// `MARKDOWN_SNAPSHOTS` names (`mise run markdown-snapshots`: the Mac here, the iPhone
/// in the simulator). Without it, nothing is drawn.
@MainActor struct Snapshots {
    #if os(iOS)
        static let platform = "iphone"
        /// An iPhone 17 Pro's width in points, and its screen scale.
        static let widths: [CGFloat] = [402]
        static let scale: CGFloat = 3
    #else
        static let platform = "mac"
        /// A conversation column in a Mac window, and a wide one past the measure.
        static let widths: [CGFloat] = [560, 900]
        static let scale: CGFloat = 2
    #endif

    @Test func drawEveryFixture() throws {
        guard let root = ProcessInfo.processInfo.environment["MARKDOWN_SNAPSHOTS"] else { return }
        let folder = URL(filePath: root).appending(path: Self.platform)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for fixture in Fixtures.all {
            for width in Self.widths {
                for scheme in [ColorScheme.light, .dark] {
                    let name = "\(fixture.name)-\(Int(width))-\(scheme == .dark ? "dark" : "light")"
                    try write(
                        page(
                            MarkdownView(fixture.text, streaming: fixture.streaming), width: width,
                            scheme: scheme),
                        to: folder.appending(path: "\(name).png"))
                }
            }
        }
        // The two variants, on the fixture a list row most often previews.
        let text = Fixtures.all.first { $0.name.hasPrefix("02") }!.text
        for scheme in [ColorScheme.light, .dark] {
            let suffix = "\(Int(Self.widths[0]))-\(scheme == .dark ? "dark" : "light")"
            try write(
                page(
                    MarkdownView(text).markdownStyle(.footnote), width: Self.widths[0],
                    scheme: scheme),
                to: folder.appending(path: "variant-footnote-\(suffix).png"))
            try write(
                page(
                    MarkdownView(text).markdownStyle(.body.preview(lines: 3)),
                    width: Self.widths[0], scheme: scheme),
                to: folder.appending(path: "variant-preview-\(suffix).png"))
        }
    }

    /// The text on the platform's own ground, inset as a conversation insets it.
    func page(_ content: some View, width: CGFloat, scheme: ColorScheme) -> some View {
        content
            .padding(16)
            .frame(width: width, alignment: .topLeading)
            .background(scheme == .dark ? Self.darkGround : .white)
            .environment(\.colorScheme, scheme)
    }

    #if os(iOS)
        static let darkGround = Color.black
    #else
        /// A Mac window's dark ground.
        static let darkGround = Color(red: 0x1e / 255, green: 0x1e / 255, blue: 0x1e / 255)
    #endif

    /// Drawn by a real hosting view in a window, not `ImageRenderer`: the renderer draws
    /// no platform-backed view (a scroll view comes out empty, a button as a
    /// placeholder), and code blocks and tables are scroll views.
    func write(_ view: some View, to url: URL) throws {
        let image = try #require(Self.draw(view), "nothing drawn for \(url.lastPathComponent)")
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), "\(url.path) not written")
    }

    #if os(iOS)
        static func draw(_ view: some View) -> CGImage? {
            let host = UIHostingController(rootView: view)
            // The window's status-bar inset would push the page down and cut its foot.
            host.safeAreaRegions = []
            let size = host.sizeThatFits(in: CGSize(width: CGFloat.infinity, height: .infinity))
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            // A window with no scene is never on screen, so the view hierarchy's own
            // snapshot comes back empty; its layers draw it.
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                host.view.layer.render(in: context.cgContext)
            }.cgImage
        }
    #else
        static func draw(_ view: some View) -> CGImage? {
            let host = NSHostingView(rootView: view)
            let size = host.fittingSize
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                return nil
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return bitmap.cgImage
        }
    #endif
}
