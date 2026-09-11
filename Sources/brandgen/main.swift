import Foundation

// brandgen: ANY brand mark, natively, with no runtime SVG engine and no
// dependency. Swift has no react-icons - SF Symbols excludes brands by
// trademark policy and every third-party option is either an icon-font
// relic or a runtime parser. But Xcode asset catalogs compile SVG with
// vector preservation and template rendering, so the only thing missing
// was a way to GET the artwork. This is it.
//
// Upstream is simple-icons (CC0, ~3.4k brands): one SVG per slug, plus a
// data file carrying each brand's OFFICIAL hex - so the generated colors
// are the brand's own, never hand-transcribed by whoever added the icon.
//
// THE CATALOG IS THE MANIFEST: one imageset per brand on disk, committed,
// and the generated enum is derived from it. No second list to drift, and
// a fresh clone builds offline - the network is only for ADDING a brand.
//
//   swift run brandgen add imdb metacritic       # fetch + regenerate
//   swift run brandgen sync                      # refetch what ships
//   swift run brandgen add spotify --into Foo    # another target in-repo
//   swift run brandgen add spotify \             # ...or any app, anywhere
//     --catalog ~/app/Assets.xcassets --out ~/app/Brands.generated.swift
//   swift run brandgen import dolbyvision \      # a mark simple-icons lacks
//     --svg ~/marks/dolby-vision.svg --hex 000000 --title "Dolby Vision" \
//     --source "Wikimedia Commons (PD)" --into MediaSpec --enum Mark
//
// LOCAL MARKS ride the same catalog. `import` copies a reviewed SVG into an
// imageset and records {title, hex, source, original} in
// `brandgen.local.json` beside the catalog (in the target's Resources dir;
// exclude it in Package.swift so it never ships). `regenerate` resolves a
// slug local-first, then upstream, else dies - one enum, two provenances,
// each stated per case. `--original` keeps the artwork's own colours
// (a flag is not a mark) instead of template rendering. `--enum` names the
// generated type: a consumer importing two catalogs must not see two
// `Brand`s.
//
// BRANDS LIVE WITH THEIR CONSUMER (see Ink/Brand.swift): resources cannot
// be tree-shaken, so a brand added to a shared base layer ships to every
// app forever. The default target is Scores because that is where the
// ratings marks are RENDERED; an app owning app-specific brands points
// this at its own catalog and links nothing extra.
//
// Deliberately additive: removing a brand is deleting its imageset dir by
// hand, then `sync`. A generator that deletes directories is a generator
// one typo away from being an incident.

// ---- locations (package-root relative, so `swift run` works anywhere) ----

let root = URL(fileURLWithPath: #filePath)  // Sources/brandgen/main.swift
    .deletingLastPathComponent()  // Sources/brandgen
    .deletingLastPathComponent()  // Sources
    .deletingLastPathComponent()  // <package root>

func flag(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: "--" + name),
        i + 1 < CommandLine.arguments.count
    else { return nil }
    return CommandLine.arguments[i + 1]
}

let target = flag("into") ?? "Scores"
let catalog =
    flag("catalog").map { URL(filePath: ($0 as NSString).expandingTildeInPath) }
    ?? root.appending(path: "Sources/\(target)/Resources/Brands.xcassets")
let enumName = flag("enum") ?? "Brand"
let generated =
    flag("out").map { URL(filePath: ($0 as NSString).expandingTildeInPath) }
    ?? root.appending(
        path: "Sources/\(target)/\(enumName == "Brand" ? "Brands" : enumName + "s").generated.swift"
    )
let localRecords = catalog.deletingLastPathComponent().appending(path: "brandgen.local.json")

let iconsBase = "https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/"
let dataURL = URL(
    string:
        "https://raw.githubusercontent.com/simple-icons/simple-icons/develop/data/simple-icons.json"
)!

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("brandgen: " + message + "\n").utf8))
    exit(1)
}

// ---- upstream ----

struct IconEntry: Decodable {
    let title: String
    let hex: String
    let slug: String?  // present only where the derived slug needed an override
}

/// simple-icons' own title -> slug rule, ported. Their data file names
/// brands by TITLE and only carries a slug where the derivation needed an
/// override, so reading hexes back out means deriving the same key they do.
func slugify(_ title: String) -> String {
    var s = title.lowercased()
    for (from, to) in [
        ("+", "plus"), (".", "dot"), ("&", "and"),
        ("đ", "d"), ("ħ", "h"), ("ı", "i"), ("ĸ", "k"),
        ("ŀ", "l"), ("ł", "l"), ("ß", "ss"), ("ŧ", "t"),
    ] {
        s = s.replacingOccurrences(of: from, with: to)
    }
    s = s.folding(options: .diacriticInsensitive, locale: nil)
    let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
    return String(s.filter { allowed.contains($0) })
}

func fetch(_ url: URL) async -> Data? {
    guard let (data, resp) = try? await URLSession.shared.data(from: url),
        (resp as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return data
}

func brandIndex() async -> [String: IconEntry] {
    guard let data = await fetch(dataURL) else { die("cannot reach the simple-icons data file") }
    guard let entries = try? JSONDecoder().decode([IconEntry].self, from: data) else {
        die("the simple-icons data file changed shape - update IconEntry")
    }
    var out: [String: IconEntry] = [:]
    for e in entries { out[e.slug ?? slugify(e.title)] = e }
    return out
}

// ---- catalog ----

func installed() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: catalog.path())) ?? []
    return names.filter { $0.hasSuffix(".imageset") }
        .map { String($0.dropLast(".imageset".count)) }
        .sorted()
}

func write(_ text: String, to url: URL) {
    do { try text.write(to: url, atomically: true, encoding: .utf8) } catch {
        die("cannot write \(url.path()): \(error.localizedDescription)")
    }
}

/// Fetch one brand's artwork into its imageset. The SVG fetch is the
/// authority on whether a slug exists: a 404 means the caller guessed,
/// and guessing silently is how a blank icon ships.
func install(_ slug: String) async {
    guard let svg = await fetch(URL(string: iconsBase + slug + ".svg")!) else {
        die("no such brand upstream: \(slug) (check the slug on simpleicons.org)")
    }
    let dir = catalog.appending(path: "\(slug).imageset")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    do { try svg.write(to: dir.appending(path: "\(slug).svg")) } catch {
        die("cannot write the svg for \(slug): \(error.localizedDescription)")
    }
    write(
        """
        {
          "images" : [ { "filename" : "\(slug).svg", "idiom" : "universal" } ],
          "info" : { "author" : "brandgen", "version" : 1 },
          "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
        }

        """, to: dir.appending(path: "Contents.json"))
}

// ---- local marks ----

/// A mark that is not upstream: everything `regenerate` needs that the
/// simple-icons index would otherwise supply, plus `original` for artwork
/// whose own colours are the point.
struct LocalEntry: Codable {
    let title: String
    let hex: String
    let source: String
    let original: Bool
}

func readLocal() -> [String: LocalEntry] {
    guard let data = try? Data(contentsOf: localRecords) else { return [:] }
    guard let out = try? JSONDecoder().decode([String: LocalEntry].self, from: data) else {
        die("\(localRecords.lastPathComponent) is not a slug -> {title, hex, source, original} map")
    }
    return out
}

func writeLocal(_ records: [String: LocalEntry]) {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? enc.encode(records) else { die("cannot encode local records") }
    write(String(decoding: data, as: UTF8.self) + "\n", to: localRecords)
}

/// Copy a reviewed local SVG into its imageset. Slugs obey the upstream
/// rule (lowercase alphanumerics) so `caseName` needs no second path.
func importLocal(_ slug: String, svg: URL, entry: LocalEntry) {
    guard !slug.isEmpty, slug.allSatisfy({ $0.isLowercase || $0.isNumber }) else {
        die("slug must be lowercase alphanumerics: \(slug)")
    }
    guard let data = try? Data(contentsOf: svg) else { die("cannot read \(svg.path())") }
    guard UInt32(entry.hex, radix: 16) != nil, entry.hex.count == 6 else {
        die("--hex wants RRGGBB, got \(entry.hex)")
    }
    let dir = catalog.appending(path: "\(slug).imageset")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    do { try data.write(to: dir.appending(path: "\(slug).svg")) } catch {
        die("cannot write the svg for \(slug): \(error.localizedDescription)")
    }
    let intent = entry.original ? "original" : "template"
    write(
        """
        {
          "images" : [ { "filename" : "\(slug).svg", "idiom" : "universal" } ],
          "info" : { "author" : "brandgen", "version" : 1 },
          "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "\(intent)" }
        }

        """, to: dir.appending(path: "Contents.json"))
    var records = readLocal()
    records[slug] = entry
    writeLocal(records)
}

/// Width over height of the imageset's artwork, read from its viewBox (or
/// width/height) at generation time. A consumer laying a mark inline
/// needs its shape as a fact, not a guess: a 24×24 symbol sits in a disc,
/// a 3:1 lockup runs with the text.
func aspect(_ slug: String) -> Double {
    let url = catalog.appending(path: "\(slug).imageset/\(slug).svg")
    guard let svg = try? String(contentsOf: url, encoding: .utf8) else {
        die("no artwork for \(slug)")
    }
    func attr(_ name: String) -> [Double]? {
        guard let r = svg.range(of: "\(name)=\""),
            let end = svg[r.upperBound...].firstIndex(of: "\"")
        else { return nil }
        let nums = svg[r.upperBound..<end].split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
        return nums.isEmpty ? nil : nums
    }
    if let vb = attr("viewBox"), vb.count == 4, vb[3] > 0 { return vb[2] / vb[3] }
    if let w = attr("width")?.first, let h = attr("height")?.first, h > 0 { return w / h }
    die("\(slug).svg carries neither a viewBox nor width/height")
}

// ---- codegen ----

let swiftKeywords: Set<String> = [
    "class", "enum", "struct", "protocol", "extension", "func",
    "import", "return", "static", "public", "internal", "private",
    "true", "false", "nil", "self", "super", "where", "default",
]

func caseName(_ slug: String) -> String {
    // Swift identifiers cannot open with a digit (backticks do not help);
    // keywords can, with backticks.
    if let first = slug.first, first.isNumber { return "_" + slug }
    return swiftKeywords.contains(slug) ? "`\(slug)`" : slug
}

/// Hex resolved to components AT GENERATION TIME - the shipped code holds
/// literals, so nothing parses a color string at runtime.
func components(_ hex: String) -> (Double, Double, Double) {
    let v = UInt32(hex, radix: 16) ?? 0
    return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}

func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

/// One resolved row per installed imageset: local record first, else the
/// upstream index, else the slug is a stranger in the catalog and the
/// generator dies rather than shipping a blank.
struct Resolved {
    let title: String
    let hex: String
    let source: String
    let original: Bool
}

func resolve(_ slug: String, _ index: [String: IconEntry], _ local: [String: LocalEntry])
    -> Resolved
{
    if let l = local[slug] {
        return Resolved(title: l.title, hex: l.hex, source: l.source, original: l.original)
    }
    if let e = index[slug] {
        return Resolved(title: e.title, hex: e.hex, source: "simple-icons (CC0)", original: false)
    }
    die(
        "\(slug) is in the catalog but neither local nor upstream - it was renamed or withdrawn; delete the imageset or fix the slug"
    )
}

func regenerate(_ index: [String: IconEntry]) {
    let slugs = installed()
    guard !slugs.isEmpty else { die("the catalog holds no brands - `brandgen add <slug>` first") }
    let local = readLocal()
    var cases: [String] = []
    var titles: [String] = []
    var colors: [String] = []
    var lums: [String] = []
    var aspects: [String] = []
    var originals: [String] = []
    var sources: [String] = []
    for slug in slugs {
        let e = resolve(slug, index, local)
        let (r, g, b) = components(e.hex)
        let name = caseName(slug)
        cases.append("    case \(name) = \"\(slug)\"")
        titles.append(
            "        case .\(name): \"\(e.title.replacingOccurrences(of: "\"", with: "\\\""))\"")
        colors.append(
            "        case .\(name): Color(red: \(fmt(r)), green: \(fmt(g)), blue: \(fmt(b)))  // #\(e.hex)"
        )
        // Rec. 709 relative luminance, resolved at generation time - the
        // fact a dark-surface consumer needs, stated instead of eyeballed.
        lums.append("        case .\(name): \(fmt(0.2126 * r + 0.7152 * g + 0.0722 * b))")
        aspects.append("        case .\(name): \(fmt(aspect(slug)))")
        if e.original { originals.append(".\(name)") }
        sources.append("//   \(slug): \(e.source)")
    }
    // Built line by line: nested multi-line literals fight the outer
    // template's indentation stripping, and a generator that emits code
    // must emit it exactly.
    let imageBlock: String
    if originals.isEmpty {
        imageBlock = [
            "",
            "    /// The mark itself, template-rendered (untinted).",
            "    public var image: Image {",
            "        Image(rawValue, bundle: .module).renderingMode(.template)",
            "    }",
        ].joined(separator: "\n")
    } else {
        imageBlock = [
            "",
            "    /// Marks whose own colours ARE the mark (a flag, not a logo): rendered",
            "    /// as authored, never template-tinted, whatever the caller passes.",
            "    public var original: Bool {",
            "        switch self {",
            "        case \(originals.joined(separator: ", ")): true",
            "        default: false",
            "        }",
            "    }",
            "",
            "    /// The mark itself; template-rendered unless `original`.",
            "    public var image: Image {",
            "        Image(rawValue, bundle: .module).renderingMode(original ? .original : .template)",
            "    }",
        ].joined(separator: "\n")
    }
    write(
        """
        // GENERATED by `swift run brandgen`. Do not edit - add or import a mark
        // and regenerate instead. Provenance per mark:
        \(sources.joined(separator: "\n"))
        //
        // This enum belongs to the module that RENDERS these marks: resources
        // cannot be tree-shaken, so brands never live in a shared base layer
        // (Ink/Brand.swift states the rule). Marks are TEMPLATE images -
        // shape, never color - so a consumer can tint them semantically while
        // `color` stays the brand's own official hex.
        import Ink
        import SwiftUI

        public enum \(enumName): String, CaseIterable, Sendable, BrandMarkable {
        \(cases.joined(separator: "\n"))

            /// The brand's own name, as its owner writes it.
            public var title: String {
                switch self {
        \(titles.joined(separator: "\n"))
                }
            }

            /// The official brand color.
            public var color: Color {
                switch self {
        \(colors.joined(separator: "\n"))
                }
            }

            /// Relative luminance of `color` (0 black … 1 white). A brand whose
            /// official color is near-black - GitHub's #181717, Metacritic's
            /// #000000 - vanishes on a dark surface, and the answer there is a
            /// shape-based treatment or an explicit tint, never a silent repaint
            /// of someone's logo.
            public var luminance: Double {
                switch self {
        \(lums.joined(separator: "\n"))
                }
            }

            /// Width over height of the artwork, from its viewBox. A symbol
            /// (≈1) sits in a disc; a lockup (≫1) runs inline with text.
            public var aspect: Double {
                switch self {
        \(aspects.joined(separator: "\n"))
                }
            }
        \(imageBlock)
        }

        """, to: generated)
    print("brandgen: \(slugs.count) marks -> \(generated.lastPathComponent)")
}

// ---- verbs ----

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "add":
    // Positional slugs only: a `--flag value` pair is never a brand.
    var slugs: [String] = []
    var skip = false
    for a in args.dropFirst() {
        if skip {
            skip = false
            continue
        }
        if a.hasPrefix("--") {
            skip = true
            continue
        }
        slugs.append(a)
    }
    guard !slugs.isEmpty else { die("usage: brandgen add <slug>...") }
    let index = await brandIndex()
    for slug in slugs {
        await install(slug)
        print("brandgen: + \(index[slug]?.title ?? slug)")
    }
    regenerate(index)
case "sync":
    let index = await brandIndex()
    let local = readLocal()
    for slug in installed() where local[slug] == nil { await install(slug) }
    regenerate(index)
case "import":
    guard args.count >= 2, let svg = flag("svg"), let hex = flag("hex"), let title = flag("title")
    else {
        die(
            "usage: brandgen import <slug> --svg <file> --hex RRGGBB --title \"<title>\" [--source \"<origin>\"] [--original]"
        )
    }
    let slug = args[1]
    importLocal(
        slug, svg: URL(filePath: (svg as NSString).expandingTildeInPath),
        entry: LocalEntry(
            title: title, hex: hex.uppercased(), source: flag("source") ?? "local",
            original: CommandLine.arguments.contains("--original")))
    print("brandgen: + \(title) (local)")
    regenerate(await brandIndex())
default:
    die(
        "usage: brandgen add <slug>... | brandgen sync | brandgen import <slug> --svg <file> --hex RRGGBB --title <title>"
    )
}
