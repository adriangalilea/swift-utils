// An app's release notes, every version's at once, where its release.json
// says they are:
//
//   no "notes"                 notes/<version>.md beside release.json
//   "notes": ["bin/notes"]     that program prints them all, each version's
//                              under a `## <version>` heading (notes kept in a
//                              database, a CMS)
//
// Each version's notes keep one grammar: `### <Group>` headings over `- `
// items. `ship release` reads them once, in the checkout before the person's
// yes, and pins them in the plan (RELEASE.md, "What a release reads from
// outside its trees"): inside the release `appcast` reads that copy, and
// `publish` reads the last release's, so the words published are the words
// approved. `check` reads them live.
import Foundation

struct Notes {
    /// Version → its notes' Markdown.
    let versions: [String: String]

    /// What the manifest names, read now; from release.json's folder.
    static func read(_ manifest: Manifest, in folder: String) -> Notes {
        guard let program = manifest.notes else {
            let dir = folder + "/notes"
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            var versions: [String: String] = [:]
            for file in files where file.hasSuffix(".md") {
                let body = (try? String(contentsOfFile: "\(dir)/\(file)", encoding: .utf8)) ?? ""
                if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    versions[String(file.dropLast(3))] = body
                }
            }
            return Notes(versions: versions)
        }
        guard !program.isEmpty else { die("release.json: \"notes\" names no program") }
        return Notes(
            document: capture(program, in: folder),
            from: "`\(program.joined(separator: " "))`")
    }

    /// The document a release pins: each version under `## <version>`.
    init(document: String, from source: String) {
        var versions: [String: String] = [:]
        var current: String?
        var lines: [Substring] = []
        func close() {
            guard let current else { return }
            guard versions[current] == nil else { die("\(source): \(current) twice") }
            let body = lines.joined(separator: "\n")
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                versions[current] = body
            }
        }
        for line in document.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                close()
                current = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                lines = []
            } else if current != nil {
                lines.append(line)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                die("\(source): \"\(line)\" is under no `## <version>` heading")
            }
        }
        close()
        self.versions = versions
    }

    init(versions: [String: String]) { self.versions = versions }

    /// A pinned copy (`ship release` wrote it).
    static func pinned(_ path: String) -> Notes {
        guard let document = try? String(contentsOfFile: path, encoding: .utf8) else {
            die("no notes at \(path)")
        }
        return Notes(document: document, from: path)
    }

    var document: String {
        versions.keys.sorted().map { "## \($0)\n\(versions[$0]!)" }.joined(separator: "\n")
    }

    func of(_ version: String) -> String? { versions[version] }
}

/// A manifest program's standard output, run from release.json's folder; a
/// program that fails stops ship.
func capture(_ program: [String], in folder: String) -> String {
    let said = program.joined(separator: " ")
    let p = Process()
    p.executableURL = URL(filePath: "/usr/bin/env")
    p.arguments = program
    p.currentDirectoryURL = URL(filePath: folder)
    let out = Pipe()
    p.standardOutput = out
    do { try p.run() } catch { die("`\(said)`: \(error.localizedDescription)") }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { die("`\(said)` exited \(p.terminationStatus)") }
    return String(decoding: data, as: UTF8.self)
}
