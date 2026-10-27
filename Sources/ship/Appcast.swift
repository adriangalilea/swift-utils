// `ship appcast`: the Sparkle feed of a release, made inside it after `ship
// build`: the feed the app already has, extended with this release's dmg and
// signed with the update key the release wrote at $SPARKLE_ED_KEY
// (`release.json` secrets). The update dialog shows one HTML document of the
// notes (Notes.swift) of every version the feed keeps.
//
// The notes document is personalised on the user's Mac: each version is a
// block tagged `data-sparkle-version=<build>`, Sparkle marks the block of the
// INSTALLED build `sparkle-installed-version`, and the stylesheet hides it and
// every older one. Someone on 1.1 updating to 1.3 reads 1.3, then "new in
// 1.2"; nobody re-reads what they already have. The match is against the
// build (CFBundleVersion), so each block carries its version's build, read
// from the feed it extends.
import Foundation

let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"

/// One version the feed carries: its marketing version and its build.
struct FeedItem {
    let version: String
    let build: Int
}

/// The items of an appcast, as Sparkle names them (`sparkle:version` is the
/// build, `sparkle:shortVersionString` the version).
func feedItems(_ xml: Data, from source: String) -> [FeedItem] {
    let document: XMLDocument
    do { document = try XMLDocument(data: xml) } catch {
        die("\(source) is not an appcast: \(error.localizedDescription)")
    }
    let items = (try? document.nodes(forXPath: "//item")) ?? []
    return items.compactMap { $0 as? XMLElement }.map { item in
        let text = { (name: String) in
            item.elements(forLocalName: name, uri: sparkleNamespace).first?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let build = text("version").flatMap(Int.init),
            let version = text("shortVersionString")
        else {
            die(
                "\(source): an item without a numeric sparkle:version and a sparkle:shortVersionString"
            )
        }
        return FeedItem(version: version, build: build)
    }
}

// MARK: - the notes

/// One span of a notes item: the grammar `ship check` gates (`### <Group>`
/// over `- ` items) with its inline vocabulary: **bold** for the headline,
/// `code` for literals, `<app>#42` (optionally "fixes"/"closes" before it)
/// citing the app's request 42, linked where release.json's `requests` says.
indirect enum Span {
    case text(String)
    case code(String)
    case bold([Span])
    case ref(String, Int)
}

struct NotesGroup {
    let title: String
    let items: [[Span]]
}

func parseInline(_ text: String, slug: String) -> [Span] {
    let inline = /\*\*([\s\S]+?)\*\*|`([^`]+)`|(?:\b(?:fixes|closes)\s+)?\b([a-z0-9-]+)#(\d+)\b/
    var spans: [Span] = []
    var last = text.startIndex
    for match in text.matches(of: inline) {
        if match.range.lowerBound > last {
            spans.append(.text(String(text[last..<match.range.lowerBound])))
        }
        if let bold = match.1 {
            spans.append(.bold(parseInline(String(bold), slug: slug)))
        } else if let code = match.2 {
            spans.append(.code(String(code)))
        } else if match.3.map(String.init) == slug, let number = match.4.flatMap({ Int($0) }) {
            spans.append(.ref(String(match.0), number))
        } else {
            spans.append(.text(String(match.0)))
        }
        last = match.range.upperBound
    }
    if last < text.endIndex { spans.append(.text(String(text[last...]))) }
    return spans
}

/// A notes file's groups, drafting comments (`<!-- … -->`) left out.
func parseNotes(_ body: String, slug: String) -> [NotesGroup] {
    let words = body.replacing(/<!--[\s\S]*?-->/, with: "")
    var groups: [(title: String, items: [String])] = []
    for line in words.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.hasPrefix("### ") {
            groups.append((String(line.dropFirst(4)), []))
        } else if line.hasPrefix("- "), !groups.isEmpty {
            groups[groups.count - 1].items.append(String(line.dropFirst(2)))
        }
    }
    return groups.map { group in
        NotesGroup(title: group.title, items: group.items.map { parseInline($0, slug: slug) })
    }
}

func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}

/// `requests`: the manifest's URL of request N (`{number}` in it); without
/// one a citation stays text.
func spansHTML(_ spans: [Span], requests: String?) -> String {
    spans.map { span in
        switch span {
        case .text(let text): escapeHTML(text)
        case .code(let text): "<code>\(escapeHTML(text))</code>"
        case .bold(let inner): "<strong>\(spansHTML(inner, requests: requests))</strong>"
        case .ref(let text, let number):
            if let requests {
                "<a href=\"\(escapeHTML(requests.replacingOccurrences(of: "{number}", with: String(number))))\">\(escapeHTML(text))</a>"
            } else {
                escapeHTML(text)
            }
        }
    }.joined()
}

/// The update dialog's notes: one block per version, newest first, the
/// offered one first. No DOCTYPE and no body, so generate_appcast embeds the
/// document as the new item's description.
func releaseNotesHTML(_ entries: [(item: FeedItem, groups: [NotesGroup])], requests: String?)
    -> String
{
    let style =
        "<style>.sparkle-installed-version,.sparkle-installed-version~.release{display:none}</style>"
    let blocks = entries.enumerated().map { index, entry in
        let head =
            index == 0
            ? ""
            : "<hr style=\"border:0; border-top:1px solid rgba(128,128,128,0.35); margin:20px 0 6px;\">"
                + "<h2 style=\"font-size:13px; font-weight:600; text-transform:lowercase; margin:0 0 2px;\">new in \(escapeHTML(entry.item.version))</h2>"
        let sections = entry.groups.map { group in
            "<h3 style=\"font-size:13px; text-transform:lowercase; letter-spacing:0.06em; opacity:0.6; margin:14px 0 4px;\">\(escapeHTML(group.title))</h3>"
                + "<ul style=\"margin:0; padding-left:18px;\">"
                + group.items.map {
                    "<li style=\"margin:4px 0; line-height:1.5;\">\(spansHTML($0, requests: requests))</li>"
                }.joined() + "</ul>"
        }.joined()
        return
            "<div class=\"release\" data-sparkle-version=\"\(entry.item.build)\">\(head)\(sections)</div>"
    }.joined()
    return
        "<div style=\"font-family:-apple-system, sans-serif; font-size:13px;\">\(style)\(blocks)</div>"
}

// MARK: - ship appcast

/// `ship appcast`: `dist/appcast.xml` for the dmg `ship build` made, with
/// the notes of every version it carries. `downloads`: the folder URL the
/// dmg is downloaded from, ending in "/".
func appcast(
    name: String, app: String, version: String, dist: String, dmg: String,
    downloads: String, requests: String?, notes: Notes, maximum: Int
) -> Never {
    let env = ProcessInfo.processInfo.environment
    guard let key = env["SPARKLE_ED_KEY"], !key.isEmpty, FileManager.default.fileExists(atPath: key)
    else {
        die(
            "ship appcast runs inside `ship release`: SPARKLE_ED_KEY names the update key's file (release.json secrets)"
        )
    }
    guard run(["which", "generate_appcast"], quiet: true).code == 0 else {
        die("no generate_appcast on PATH (Sparkle's tools)")
    }
    guard maximum >= 1 else { die("--maximum-versions must be at least 1") }
    let slug = name.lowercased()
    let plist = "\(app)/Contents/Info.plist"
    let read = { (key: String) -> String? in
        let r = run(["/usr/libexec/PlistBuddy", "-c", "Print :\(key)", plist], quiet: true)
        return r.code == 0 && !r.out.isEmpty ? r.out : nil
    }
    guard read("CFBundleShortVersionString") == version else {
        die(
            "\(plist) carries version \(read("CFBundleShortVersionString") ?? "none"), not \(version)"
        )
    }
    guard let build = read("CFBundleVersion").flatMap(Int.init) else {
        die("\(plist) carries no numeric CFBundleVersion: Sparkle orders updates by it")
    }
    // Without it generate_appcast writes the item unsigned and says nothing.
    guard read("SUPublicEDKey") != nil else {
        die("\(plist) carries no SUPublicEDKey: no installed copy could trust a signed update")
    }
    guard FileManager.default.fileExists(atPath: dmg) else { die("no \(dmg): ship build first") }

    // generate_appcast works in a directory of its own: the feed it extends
    // (appcast.xml), each archive and, beside each under its stem, its notes.
    let stage = "\(dist)/appcast"
    let staged = "\(stage)/appcast.xml"
    try? FileManager.default.removeItem(atPath: stage)
    do {
        try FileManager.default.createDirectory(atPath: stage, withIntermediateDirectories: true)
    } catch { die("create \(stage): \(error.localizedDescription)") }

    step("the feed it extends")
    let existing = "\(dist)/appcast.xml"
    var past: [FeedItem] = []
    if FileManager.default.fileExists(atPath: existing) {
        do { try FileManager.default.copyItem(atPath: existing, toPath: staged) } catch {
            die("copy \(existing): \(error.localizedDescription)")
        }
        past = feedItems(FileManager.default.contents(atPath: staged) ?? Data(), from: existing)
        print("  \(existing): \(past.count) item(s)")
    } else {
        guard let url = read("SUFeedURL") else {
            die("no feed to extend: no \(existing), and \(plist) names no SUFeedURL")
        }
        let fetched = run(
            ["curl", "-sSL", "-o", staged, "-w", "%{http_code}", url], quiet: true)
        let status = fetched.out.split(separator: "\n").last.map(String.init) ?? ""
        if status == "404" {
            try? FileManager.default.removeItem(atPath: staged)
            print("  \(url): none yet (404), the first item")
        } else if fetched.code == 0, status == "200" {
            past = feedItems(FileManager.default.contents(atPath: staged) ?? Data(), from: url)
            print("  \(url): \(past.count) item(s)")
        } else {
            die("cannot read the feed at \(url): \(fetched.out)")
        }
    }
    if let newest = past.max(by: { $0.build < $1.build }), newest.build >= build {
        die(
            "\(version) is build \(build), but the feed already carries build \(newest.build) (\(newest.version)): bump CFBundleVersion"
        )
    }

    step("the notes")
    // The versions the feed keeps once this one joins it: the dialog never
    // promises more history than the feed carries.
    let kept =
        [FeedItem(version: version, build: build)]
        + past.sorted { $0.build > $1.build }.prefix(maximum - 1)
    var entries: [(item: FeedItem, groups: [NotesGroup])] = []
    for item in kept {
        let origin = notes.origin(of: item.version)
        guard let body = notes.of(item.version) else {
            if item.build == build {
                die("\(origin) has no notes: the version released needs them")
            }
            print("  \(item.version) (build \(item.build)): none from \(origin), left out")
            continue
        }
        let groups = parseNotes(body, slug: slug)
        guard groups.contains(where: { !$0.items.isEmpty }) else {
            die("\(origin) keeps no '### <Group>' with '- ' items")
        }
        entries.append((item, groups))
        print("  \(item.version) (build \(item.build)): \(origin)")
    }
    let stem = ((dmg as NSString).lastPathComponent as NSString).deletingPathExtension
    let html = "\(dist)/\(stem).html"
    do {
        try releaseNotesHTML(entries, requests: requests).write(
            toFile: html, atomically: true, encoding: .utf8)
        try FileManager.default.linkItem(atPath: html, toPath: "\(stage)/\(stem).html")
        try FileManager.default.linkItem(atPath: dmg, toPath: "\(stage)/\(stem).dmg")
    } catch { die("stage the notes and the dmg: \(error.localizedDescription)") }

    step("generate_appcast")
    must([
        "generate_appcast", "--ed-key-file", key, "--download-url-prefix", downloads,
        "--maximum-versions", String(maximum), stage,
    ])
    guard let made = FileManager.default.contents(atPath: staged),
        let document = try? XMLDocument(data: made),
        let item = (try? document.nodes(forXPath: "//item"))?.compactMap({ $0 as? XMLElement })
            .first(where: {
                $0.elements(forLocalName: "version", uri: sparkleNamespace).first?.stringValue
                    == String(build)
            })
    else { die("generate_appcast left no item for build \(build) in \(staged)") }
    let signature = item.elements(forName: "enclosure").first?.attribute(
        forLocalName: "edSignature", uri: sparkleNamespace)?.stringValue
    guard let signature, !signature.isEmpty else {
        die("generate_appcast left build \(build) unsigned")
    }
    guard item.elements(forName: "description").first != nil else {
        die("generate_appcast did not embed \(stem).html as build \(build)'s notes")
    }
    do {
        try? FileManager.default.removeItem(atPath: existing)
        try FileManager.default.moveItem(atPath: staged, toPath: existing)
        try FileManager.default.removeItem(atPath: stage)
    } catch { die("move the feed into \(existing): \(error.localizedDescription)") }
    print(
        "\nappcast \(name) \(version) (build \(build)): \(existing), notes \(html) for \(entries.map(\.item.version).joined(separator: ", "))"
    )
    exit(0)
}
