import Foundation
import GitKit
import SwiftUI
import Syntax

/// What a `DiffView` was given, as one value: a parsed diff, one file, git's text, or two
/// texts to compare. Its `key` names it in the caches, so a view rebuilt by its parent
/// finds its work already done.
struct DiffInput: Sendable {
    enum Kind: Sendable, Hashable {
        case diff(Git.Diff)
        case file(Git.FileDiff)
        case unified(String, path: String?)
        case texts(old: String, new: String, path: String?, startLine: Int)
    }

    let kind: Kind
    let key: Int

    init(_ kind: Kind) {
        self.kind = kind
        key = kind.hashValue
    }

    /// Roughly how many lines: small inputs are read and painted in the frame that shows
    /// them (no flash of an empty well); big ones off the main thread.
    var size: Int {
        switch kind {
        case .diff(let diff): diff.files.reduce(0) { $0 + $1.lineCount }
        case .file(let file): file.lineCount
        case .unified(let text, _): text.utf8.count / 40
        case .texts(let old, let new, _, _): (old.utf8.count + new.utf8.count) / 40
        }
    }

    func files(context: Int) -> [Git.FileDiff] {
        switch kind {
        case .diff(let diff): return diff.files
        case .file(let file): return [file]
        case .unified(let text, let path):
            // git's own output reads strictly (several files, renames, modes); anything
            // else, or git's output that does not parse, as a fragment someone wrote.
            if text.hasPrefix("diff --git ") || text.contains("\ndiff --git "),
                let diff = try? Git.Diff(parsing: text), !diff.files.isEmpty
            {
                return diff.files
            }
            return [Git.FileDiff(snippet: text, path: path)]
        case .texts(let old, let new, let path, let start):
            return [
                Git.FileDiff(old: old, new: new, path: path, context: context, startLine: start)
            ]
        }
    }
}

/// One file ready to draw: its lines flattened in order, each with the text as drawn
/// (tabs set as spaces) and the stretches of words that changed.
struct RenderedFile: Sendable, Identifiable {
    struct Line: Sendable {
        let hunk: Int
        let line: Git.Line
        let display: String
        let words: [Range<Int>]
        /// The line's place in its side's text (`DiffPainter` colors each side whole).
        let oldIndex: Int?
        let newIndex: Int?
    }

    let file: Git.FileDiff
    let id: String
    let key: Int
    let lines: [Line]
    /// Index of each hunk's first line in `lines`.
    let hunkStarts: [Int]
    /// The longest line, in characters.
    let columns: Int
    /// Digits of the largest line number (the gutter's width).
    let digits: Int
    let hasNumbers: Bool
    let language: String?

    init(_ file: Git.FileDiff, salt: Int) {
        self.file = file
        id = file.id
        var hasher = Hasher()
        hasher.combine(file)
        hasher.combine(salt)
        key = hasher.finalize()
        var lines: [Line] = []
        var starts: [Int] = []
        var columns = 0
        var largest = 0
        var numbered = false
        var oldCount = 0
        var newCount = 0
        for (h, hunk) in file.hunks.enumerated() {
            starts.append(lines.count)
            let shown = hunk.lines.map { Self.expandTabs($0.text) }
            var displayHunk = hunk
            for index in displayHunk.lines.indices { displayHunk.lines[index].text = shown[index] }
            let words = Git.Intraline.pairs(in: displayHunk)
            for (index, line) in hunk.lines.enumerated() {
                let display = shown[index]
                columns = max(columns, display.count)
                largest = max(largest, line.old ?? 0, line.new ?? 0)
                if line.old != nil || line.new != nil { numbered = true }
                var oldIndex: Int?
                var newIndex: Int?
                if line.kind != .added {
                    oldIndex = oldCount
                    oldCount += 1
                }
                if line.kind != .removed {
                    newIndex = newCount
                    newCount += 1
                }
                lines.append(
                    Line(
                        hunk: h, line: line, display: display, words: words[index] ?? [],
                        oldIndex: oldIndex,
                        newIndex: newIndex))
            }
        }
        self.lines = lines
        hunkStarts = starts
        self.columns = columns
        digits = max(2, String(largest).count)
        hasNumbers = numbered
        language = DiffLanguage.of(file.path)
    }

    /// The lines of hunk `h`, as indices into `lines`.
    func range(of hunk: Int) -> Range<Int> {
        hunkStarts[hunk]..<(hunk + 1 < hunkStarts.count ? hunkStarts[hunk + 1] : lines.count)
    }

    static func expandTabs(_ text: String, width: Int = 4) -> String {
        guard text.contains("\t") else { return text }
        var out = ""
        var column = 0
        for character in text {
            if character == "\t" {
                let pad = width - column % width
                out += String(repeating: " ", count: pad)
                column += pad
            } else {
                out.append(character)
                column += 1
            }
        }
        return out
    }
}

struct DiffDocument: Sendable {
    let key: Int
    let files: [RenderedFile]

    init(_ input: DiffInput, context: Int) {
        var hasher = Hasher()
        hasher.combine(input.key)
        hasher.combine(context)
        key = hasher.finalize()
        let salt = key
        files = input.files(context: context).map { RenderedFile($0, salt: salt) }
    }
}

/// A file's lines painted: syntax inks (when it has a language) under the changed words'
/// tint. Each side of the file is colored as one text, so a string or comment that spans
/// lines keeps its color, in chunks under `Syntax.ceiling`.
enum DiffPainter {
    static func paint(
        _ file: RenderedFile, palette: DiffPalette, appearance: Syntax.Appearance, syntax: Bool
    )
        -> [AttributedString]
    {
        var oldSide: [AttributedString]?
        var newSide: [AttributedString]?
        if syntax, let language = file.language {
            oldSide = colored(
                file.lines.filter { $0.oldIndex != nil }.map(\.display), language, appearance)
            newSide = colored(
                file.lines.filter { $0.newIndex != nil }.map(\.display), language, appearance)
        }
        return file.lines.map { line in
            var text: AttributedString
            if let index = line.newIndex, let side = newSide, index < side.count {
                text = side[index]
            } else if let index = line.oldIndex, let side = oldSide, index < side.count {
                text = side[index]
            } else {
                text = AttributedString(line.display)
            }
            if line.line.kind != .context, !line.words.isEmpty {
                let tint = palette.word(line.line.kind)
                let characters = text.characters
                for range in line.words where range.upperBound <= characters.count {
                    let start = characters.index(characters.startIndex, offsetBy: range.lowerBound)
                    let end = characters.index(start, offsetBy: range.count)
                    text[start..<end].backgroundColor = tint
                }
            }
            return text
        }
    }

    /// `lines` highlighted as one text, chunked at line boundaries under the engine's
    /// ceiling, split back into lines. Nil when the grammar gave nothing usable.
    static func colored(_ lines: [String], _ language: String, _ appearance: Syntax.Appearance)
        -> [AttributedString]?
    {
        guard !lines.isEmpty else { return [] }
        var out: [AttributedString] = []
        out.reserveCapacity(lines.count)
        var chunk: [String] = []
        var bytes = 0
        let limit = Syntax.ceiling * 3 / 4
        func flush() {
            guard !chunk.isEmpty else { return }
            let joined = chunk.joined(separator: "\n")
            let colored = Syntax.highlight(joined, language: language, on: appearance)
            out += split(colored, expecting: chunk.count) ?? chunk.map { AttributedString($0) }
            chunk = []
            bytes = 0
        }
        for line in lines {
            let size = line.utf8.count + 1
            if bytes + size > limit { flush() }
            chunk.append(line)
            bytes += size
        }
        flush()
        return out.count == lines.count ? out : nil
    }

    static func split(_ text: AttributedString, expecting count: Int) -> [AttributedString]? {
        var out: [AttributedString] = []
        out.reserveCapacity(count)
        var start = text.startIndex
        var index = text.startIndex
        let characters = text.characters
        while index < text.endIndex {
            if characters[index] == "\n" {
                out.append(AttributedString(text[start..<index]))
                start = characters.index(after: index)
            }
            index = characters.index(after: index)
        }
        out.append(AttributedString(text[start..<text.endIndex]))
        return out.count == count ? out : nil
    }
}

/// The work a diff takes, kept between frames and views: parsed documents and painted
/// files, a few dozen of each, the oldest forgotten first. One lock; nothing in it is
/// touched while drawing except to read.
final class DiffStore: @unchecked Sendable {
    static let shared = DiffStore()
    private let lock = NSLock()
    private var documents: [Int: DiffDocument] = [:]
    private var documentOrder: [Int] = []
    private var painted: [String: [AttributedString]] = [:]
    private var paintedOrder: [String] = []

    func document(_ key: Int) -> DiffDocument? { lock.withLock { documents[key] } }

    func remember(_ document: DiffDocument) {
        lock.withLock {
            if documents[document.key] == nil {
                documentOrder.append(document.key)
                if documentOrder.count > 48 { documents[documentOrder.removeFirst()] = nil }
            }
            documents[document.key] = document
        }
    }

    func painted(_ key: String) -> [AttributedString]? { lock.withLock { painted[key] } }

    func remember(_ key: String, _ lines: [AttributedString]) {
        lock.withLock {
            if painted[key] == nil {
                paintedOrder.append(key)
                if paintedOrder.count > 96 { painted[paintedOrder.removeFirst()] = nil }
            }
            painted[key] = lines
        }
    }

    static func paintKey(_ file: RenderedFile, _ scheme: ColorScheme, _ syntax: Bool) -> String {
        "\(file.key)|\(scheme == .dark ? "d" : "l")|\(syntax ? "s" : "p")"
    }
}

/// A file's language, by its extension or name, in the names highlight.js knows. Nil
/// means plain: guessing a grammar from content paints prose as code.
enum DiffLanguage {
    static func of(_ path: String) -> String? {
        let name = (path as NSString).lastPathComponent.lowercased()
        switch name {
        case "makefile", "gnumakefile": return "makefile"
        case "dockerfile", "containerfile": return "dockerfile"
        case "package.swift": return "swift"
        case "gemfile", "podfile", "fastfile": return "ruby"
        default: break
        }
        let ext = (name as NSString).pathExtension
        return extensions[ext]
    }

    static let extensions: [String: String] = [
        "swift": "swift", "m": "objectivec", "mm": "objectivec", "h": "objectivec", "c": "c",
        "cc": "cpp", "cpp": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp", "js": "javascript",
        "mjs": "javascript", "cjs": "javascript", "jsx": "javascript", "ts": "typescript",
        "tsx": "typescript",
        "mts": "typescript", "json": "json", "jsonc": "json", "md": "markdown",
        "markdown": "markdown",
        "py": "python", "rb": "ruby", "go": "go", "rs": "rust", "java": "java", "kt": "kotlin",
        "kts": "kotlin",
        "sh": "bash", "bash": "bash", "zsh": "bash", "fish": "bash", "yml": "yaml", "yaml": "yaml",
        "toml": "ini", "ini": "ini", "xml": "xml", "plist": "xml", "html": "xml", "htm": "xml",
        "svg": "xml",
        "css": "css", "scss": "scss", "less": "less", "sql": "sql", "lua": "lua", "php": "php",
        "cs": "csharp",
        "dart": "dart", "scala": "scala", "ex": "elixir", "exs": "elixir", "hs": "haskell",
        "vim": "vim",
        "gradle": "gradle", "r": "r", "pl": "perl", "proto": "protobuf", "graphql": "graphql",
        "nix": "nix",
        "cmake": "cmake",
    ]
}
