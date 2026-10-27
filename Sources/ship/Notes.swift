// An app's release notes, where its release.json says they are:
//
//   no "notes"                    notes/<version>.md beside release.json
//   "notes": ["bin/notes"]        that program prints them, given the version
//                                 as its last argument
//
// A program reads notes kept anywhere else (a database, a CMS) without
// copying them into files first. It runs in release.json's folder, without
// the release's keys in its environment; printing nothing means the version
// has no notes, and a failing program stops ship. `check`, `publish` and
// `appcast` read the notes only through here, so the words gated are the
// words published.
import Foundation

struct Notes {
    let folder: String
    let program: [String]?
    /// Variables a release sets, withheld from the program.
    let withheld: Set<String>

    static func ofApp() -> Notes {
        let (manifest, folder) = appManifest()
        if let program = manifest.notes, program.isEmpty {
            die("release.json: \"notes\" names no program")
        }
        return Notes(
            folder: folder, program: manifest.notes,
            withheld: reserved.union((manifest.secrets ?? [:]).keys))
    }

    /// Where a version's notes come from, in words.
    func origin(of version: String) -> String {
        guard let program else { return "notes/\(version).md" }
        return "`\((program + [version]).joined(separator: " "))`"
    }

    /// The Markdown of `version`; nil when there is none.
    func of(_ version: String) -> String? {
        let body: String
        if let program {
            let p = Process()
            p.executableURL = URL(filePath: "/usr/bin/env")
            p.arguments = program + [version]
            p.currentDirectoryURL = URL(filePath: folder)
            p.environment = ProcessInfo.processInfo.environment.filter {
                !withheld.contains($0.key)
            }
            let out = Pipe()
            p.standardOutput = out
            do { try p.run() } catch {
                die("\(origin(of: version)): \(error.localizedDescription)")
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                die("\(origin(of: version)) exited \(p.terminationStatus)")
            }
            body = String(decoding: data, as: UTF8.self)
        } else {
            body =
                (try? String(contentsOfFile: "\(folder)/notes/\(version).md", encoding: .utf8))
                ?? ""
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : body
    }
}
