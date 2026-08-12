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

let root = URL(fileURLWithPath: #filePath)          // Sources/brandgen/main.swift
    .deletingLastPathComponent()                    // Sources/brandgen
    .deletingLastPathComponent()                    // Sources
    .deletingLastPathComponent()                    // <package root>

func flag(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: "--" + name),
          i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

let target = flag("into") ?? "Scores"
let catalog = flag("catalog").map { URL(filePath: ($0 as NSString).expandingTildeInPath) }
    ?? root.appending(path: "Sources/\(target)/Resources/Brands.xcassets")
let generated = flag("out").map { URL(filePath: ($0 as NSString).expandingTildeInPath) }
    ?? root.appending(path: "Sources/\(target)/Brands.generated.swift")

let iconsBase = "https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/"
let dataURL = URL(string: "https://raw.githubusercontent.com/simple-icons/simple-icons/develop/data/simple-icons.json")!

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("brandgen: " + message + "\n").utf8))
    exit(1)
}

// ---- upstream ----

struct IconEntry: Decodable {
    let title: String
    let hex: String
    let slug: String?   // present only where the derived slug needed an override
}

/// simple-icons' own title -> slug rule, ported. Their data file names
/// brands by TITLE and only carries a slug where the derivation needed an
/// override, so reading hexes back out means deriving the same key they do.
func slugify(_ title: String) -> String {
    var s = title.lowercased()
    for (from, to) in [("+", "plus"), (".", "dot"), ("&", "and"),
                       ("đ", "d"), ("ħ", "h"), ("ı", "i"), ("ĸ", "k"),
                       ("ŀ", "l"), ("ł", "l"), ("ß", "ss"), ("ŧ", "t")] {
        s = s.replacingOccurrences(of: from, with: to)
    }
    s = s.folding(options: .diacriticInsensitive, locale: nil)
    let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
    return String(s.filter { allowed.contains($0) })
}

func fetch(_ url: URL) async -> Data? {
    guard let (data, resp) = try? await URLSession.shared.data(from: url),
          (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
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
    do { try text.write(to: url, atomically: true, encoding: .utf8) }
    catch { die("cannot write \(url.path()): \(error.localizedDescription)") }
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
    do { try svg.write(to: dir.appending(path: "\(slug).svg")) }
    catch { die("cannot write the svg for \(slug): \(error.localizedDescription)") }
    write("""
    {
      "images" : [ { "filename" : "\(slug).svg", "idiom" : "universal" } ],
      "info" : { "author" : "brandgen", "version" : 1 },
      "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
    }

    """, to: dir.appending(path: "Contents.json"))
}

// ---- codegen ----

let swiftKeywords: Set<String> = ["class", "enum", "struct", "protocol", "extension", "func",
                                  "import", "return", "static", "public", "internal", "private",
                                  "true", "false", "nil", "self", "super", "where", "default"]

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

func regenerate(_ index: [String: IconEntry]) {
    let slugs = installed()
    guard !slugs.isEmpty else { die("the catalog holds no brands - `brandgen add <slug>` first") }
    var cases: [String] = [], titles: [String] = [], colors: [String] = [], lums: [String] = []
    for slug in slugs {
        guard let e = index[slug] else {
            die("\(slug) is in the catalog but not upstream - it was renamed or withdrawn; delete the imageset or fix the slug")
        }
        let (r, g, b) = components(e.hex)
        cases.append("    case \(caseName(slug)) = \"\(slug)\"")
        titles.append("        case .\(caseName(slug)): \"\(e.title.replacingOccurrences(of: "\"", with: "\\\""))\"")
        colors.append("        case .\(caseName(slug)): Color(red: \(fmt(r)), green: \(fmt(g)), blue: \(fmt(b)))  // #\(e.hex)")
        // Rec. 709 relative luminance, resolved at generation time - the
        // fact a dark-surface consumer needs, stated instead of eyeballed.
        lums.append("        case .\(caseName(slug)): \(fmt(0.2126 * r + 0.7152 * g + 0.0722 * b))")
    }
    write("""
    // GENERATED by `swift run brandgen`. Do not edit - add a brand and
    // regenerate instead. Artwork + colors: simple-icons (CC0).
    //
    // This enum belongs to the module that RENDERS these marks: resources
    // cannot be tree-shaken, so brands never live in a shared base layer
    // (Ink/Brand.swift states the rule). Marks are TEMPLATE images -
    // shape, never color - so a consumer can tint them semantically while
    // `color` stays the brand's own official hex.
    import Ink
    import SwiftUI

    public enum Brand: String, CaseIterable, Sendable, BrandMarkable {
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

        /// The mark itself, template-rendered (untinted).
        public var image: Image {
            Image(rawValue, bundle: .module).renderingMode(.template)
        }
    }

    """, to: generated)
    print("brandgen: \(slugs.count) brands -> \(generated.lastPathComponent)")
}

// ---- verbs ----

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "add":
    let slugs = Array(args.dropFirst())
    guard !slugs.isEmpty else { die("usage: brandgen add <slug>...") }
    let index = await brandIndex()
    for slug in slugs {
        await install(slug)
        print("brandgen: + \(index[slug]?.title ?? slug)")
    }
    regenerate(index)
case "sync":
    let index = await brandIndex()
    for slug in installed() { await install(slug) }
    regenerate(index)
default:
    die("usage: brandgen add <slug>... | brandgen sync")
}
