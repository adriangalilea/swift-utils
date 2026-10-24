import Foundation
import GitKit
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import GitViews

enum Inputs {
    static let folder = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    /// The scenario's agent session (`Tests/GitKitTests/Fixtures/scenario`): every kind of
    /// change git has.
    static var agent: Git.Diff {
        try! Git.Diff(parsing: Data(contentsOf: folder.appending(path: "agent.diff")))
    }

    /// A long file with `edits` scattered changes, for the plan and the clock.
    static func long(lines: Int, every: Int = 37) -> Git.FileDiff {
        let old = (1...lines).map { "    let value\($0) = compute(\($0), scale: 2) // step \($0)" }
        var new = old
        for index in stride(from: 5, to: lines, by: every) {
            new[index] =
                "    let value\(index + 1) = compute(\(index + 1), scale: 3) // step \(index + 1)"
        }
        return Git.FileDiff(
            old: old.joined(separator: "\n") + "\n", new: new.joined(separator: "\n") + "\n",
            path: "Long.swift",
            context: 3)
    }
}

struct RowPlans {
    /// A run of unchanged lines longer than the context folds to the context on each side.
    @Test func longContextFolds() throws {
        let file = Git.FileDiff(
            old: (1...30).map { "l\($0)" }.joined(separator: "\n") + "\n",
            new: (1...30).map { $0 == 3 || $0 == 28 ? "L\($0)" : "l\($0)" }.joined(separator: "\n")
                + "\n",
            context: 20)
        let rendered = RenderedFile(file, salt: 0)
        let plan = DiffRowPlan(split: false, context: 3)
        let rows = plan.rows(rendered).rows
        let folds = rows.compactMap { row -> Range<Int>? in
            if case .fold(let range) = row { return range }
            return nil
        }
        #expect(folds.count == 1)
        #expect(folds[0].count == 30 - 2 - 2 * 3 - 2 - 2)  // between the two edits, less 3 each side
        var open = plan
        open.expandedFolds = [folds[0].lowerBound]
        #expect(open.rows(rendered).rows.count == rendered.lines.count + 0)
    }

    /// Lines opened above a hunk draw as its unchanged lines, not folded again: the fold
    /// the opening records starts where the hunk's lines start.
    @Test func openedLinesStayOpen() throws {
        let old = (1...60).map { "l\($0)" }.joined(separator: "\n") + "\n"
        let new = old.replacingOccurrences(of: "l5\n", with: "L5\n")
            .replacingOccurrences(of: "l50\n", with: "L50\n")
        let file = Git.FileDiff(old: old, new: new, context: 3)
        let wider = try #require(file.revealing(above: 1, in: new, limit: 20))
        let rendered = RenderedFile(wider, salt: 0)
        var plan = DiffRowPlan(split: false, context: 3)
        let folded = plan.rows(rendered).rows.filter { if case .fold = $0 { true } else { false } }
        #expect(folded.count == 1)
        plan.expandedFolds = [rendered.range(of: 1).lowerBound]
        let rows = plan.rows(rendered).rows
        #expect(!rows.contains { if case .fold = $0 { true } else { false } })
        #expect(
            rows.filter { if case .line = $0 { true } else { false } }.count == rendered.lines.count
        )
    }

    /// Split rows put a removed run beside the added run after it.
    @Test func splitPairs() {
        let file = Git.FileDiff(old: "a\nb\nc\nd\n", new: "a\nB\nC\nX\nd\n")
        let rendered = RenderedFile(file, salt: 0)
        let rows = DiffRowPlan(split: true, context: 3).rows(rendered).rows
        let pairs = rows.compactMap { row -> String? in
            guard case .pair(let old, let new) = row else { return nil }
            let say = { (i: Int?) in i.map { rendered.lines[$0].line.text } ?? "·" }
            return "\(say(old))|\(say(new))"
        }
        #expect(pairs == ["a|a", "b|B", "c|C", "·|X", "d|d"])
    }

    /// A preview draws its budget of lines and says how many more there are.
    @Test func previewBudget() {
        let rendered = RenderedFile(Inputs.long(lines: 200, every: 9), salt: 0)
        var plan = DiffRowPlan(split: false, context: 3)
        plan.budget = 8
        let (rows, hidden) = plan.rows(rendered)
        let drawn = rows.filter {
            if case .line = $0 { return true }
            return false
        }
        #expect(drawn.count == 8)
        #expect(hidden == rendered.lines.count - 8)
        #expect(rows.last == .more(hidden: hidden))
    }

    /// The selection's actions sit right under its last line.
    @Test func actionsFollowTheSelection() {
        let rendered = RenderedFile(Git.FileDiff(old: "a\nb\nc\n", new: "a\nB\nc\n"), salt: 0)
        var plan = DiffRowPlan(split: false, context: 3)
        plan.selection = 1...2
        plan.actions = true
        let rows = plan.rows(rendered).rows
        let at = rows.firstIndex(of: .actions)
        #expect(at.map { rows[$0 - 1] } == .line(2))
    }
}

struct Performance {
    /// A 10,000-line diff is read, laid out and painted (intraline included) in well under
    /// a second off the main thread; drawing it is lazy, so this is the whole cost.
    @Test func tenThousandLines() {
        let file = Inputs.long(lines: 10_000, every: 7)
        let started = Date()
        let rendered = RenderedFile(file, salt: 0)
        let read = Date().timeIntervalSince(started)
        let rows = DiffRowPlan(split: false, context: 3).rows(rendered).rows
        let planned = Date().timeIntervalSince(started) - read
        let painted = DiffPainter.paint(
            rendered, palette: .light, appearance: .light, syntax: false)
        let total = Date().timeIntervalSince(started)
        #expect(rendered.lines.count > 9_000)
        #expect(rows.count > 9_000)
        #expect(painted.count == rendered.lines.count)
        #expect(planned < 0.1, "planning rows took \(planned)s")
        #expect(total < 2, "reading and painting took \(total)s (read \(read)s)")
    }

    @Test func syntaxPaintsEverySideInChunks() {
        let file = Inputs.long(lines: 3_000, every: 11)
        let rendered = RenderedFile(file, salt: 0)
        let painted = DiffPainter.paint(rendered, palette: .dark, appearance: .dark, syntax: true)
        #expect(painted.count == rendered.lines.count)
        #expect(zip(painted, rendered.lines).allSatisfy { String($0.characters) == $1.display })
    }
}

/// The diff drawn light and dark at a phone's and a Mac's widths, as PNGs into the folder
/// `GITVIEWS_SNAPSHOTS` names. Without it, nothing is drawn.
@MainActor struct Snapshots {
    #if os(iOS)
        static let platform = "iphone"
        static let widths: [CGFloat] = [402]
        static let scale: CGFloat = 3
    #else
        static let platform = "mac"
        static let widths: [CGFloat] = [560, 1100]
        static let scale: CGFloat = 2
    #endif

    @Test func drawTheDiff() throws {
        guard let root = ProcessInfo.processInfo.environment["GITVIEWS_SNAPSHOTS"] else { return }
        let folder = URL(filePath: root).appending(path: Self.platform)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let agent = Inputs.agent
        let swift = agent.files.first { $0.path == "Sources/Syntax/Syntax.swift" }!
        let cases: [(String, AnyView)] = [
            ("file", AnyView(DiffView(swift))),
            ("agent", AnyView(DiffView(Git.Diff(files: Array(agent.files.prefix(7)))))),
            ("card", AnyView(DiffView(swift).diffMaxLines(8))),
            (
                "edit",
                AnyView(
                    DiffView(
                        old:
                            "func total(_ items: [Item]) -> Int {\n    items.reduce(0) { $0 + $1.count }\n}\n",
                        new:
                            "func total(_ items: [Item]) -> Int {\n    // Only the visible ones count.\n    items.filter(\\.visible).reduce(0) { $0 + $1.count }\n}\n",
                        path: "Totals.swift"))
            ),
            (
                "snippet",
                AnyView(
                    DiffView(unified: "-let tail: Tail = 4\n+let tail: Tail = 6\n let head = 0"))
            ),
            ("split", AnyView(DiffView(swift).diffStyle(.split))),
            ("nowrap", AnyView(DiffView(swift).diffWrap(false))),
        ]
        for (name, view) in cases {
            for width in Self.widths {
                for scheme in [ColorScheme.light, .dark] {
                    try write(
                        page(view, width: width, scheme: scheme),
                        to: folder.appending(
                            path: "\(name)-\(Int(width))-\(scheme == .dark ? "dark" : "light").png")
                    )
                }
            }
        }
    }

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
        static let darkGround = Color(red: 0x1e / 255, green: 0x1e / 255, blue: 0x1e / 255)
    #endif

    func write(_ view: some View, to url: URL) throws {
        let image = try #require(Self.draw(view), "nothing drawn for \(url.lastPathComponent)")
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), "\(url.path) not written")
    }

    /// Settle twice: a diff measures its width after its first layout (split or not, one
    /// gutter or two), and paints big files after the frame that shows them.
    static func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.4)) }

    #if os(iOS)
        static func draw(_ view: some View) -> CGImage? {
            let host = UIHostingController(rootView: view)
            host.safeAreaRegions = []
            var size = host.sizeThatFits(in: CGSize(width: CGFloat.infinity, height: .infinity))
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            settle()
            size = host.sizeThatFits(in: CGSize(width: CGFloat.infinity, height: .infinity))
            window.frame = CGRect(origin: .zero, size: size)
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                host.view.layer.render(in: context.cgContext)
            }.cgImage
        }
    #else
        static func draw(_ view: some View) -> CGImage? {
            let host = NSHostingView(rootView: view)
            var size = host.fittingSize
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            settle()
            size = host.fittingSize
            window.setContentSize(size)
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
