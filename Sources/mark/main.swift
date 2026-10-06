// mark: a Mac app's icon from its one source, the Icon Composer package
// `<Name>.icon` (icon.json + Assets/, the layers as SVG). Icon Composer opens
// and edits it, git diffs it, and every icon file is compiled from it, so
// there is never a second drawing.
//
//   mark build <Name>.icon --out <dir> [--png <file>]
//       actool → <dir>/Assets.car (the glass icon macOS 26 draws, every
//       appearance) and <dir>/<Name>.icns (the flat fallback: Finder's older
//       paths, the dmg's volume icon); --png writes the 512 px rendering, for
//       a site's project row.
//   mark preview <Name>.icon [--all]
//       Apple's own renderer (Icon Composer's ictool) draws the icon at 256
//       down to 20 px on dark and light, into a page it opens: the review,
//       before anything ships. --all adds every appearance a person can pick
//       (dark, clear, tinted); the default is what nearly everyone sees.
//
// Layers are SVG and plain vector: Icon Composer draws SVG layers and
// ignores SVG filters, so an effect (a fillet, a glow) is baked into the
// geometry. A layer as PNG is refused: it is a rendering, not the drawing,
// and Apple's pipeline colours it differently from the same art as SVG.
import Foundation

// Line-buffered even into a pipe, as ship does.
setvbuf(stdout, nil, _IOLBF, 0)

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("mark: \(message)\n".utf8))
    exit(1)
}

/// Runs a tool; its output is kept, and shown only when it fails.
@discardableResult
func run(_ argv: [String]) -> String {
    let p = Process()
    p.executableURL = URL(filePath: "/usr/bin/env")
    p.arguments = argv
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { die("\(argv[0]): \(error.localizedDescription)") }
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    if p.terminationStatus != 0 {
        die("\(argv.joined(separator: " ")) exited \(p.terminationStatus)\n\(out)")
    }
    return out
}

let args = Array(CommandLine.arguments.dropFirst())
func value(_ flag: String) -> String? {
    args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
}
let usage =
    "usage: mark build <Name>.icon --out <dir> [--png <file>] | mark preview <Name>.icon [--all]"
guard args.count >= 2, ["build", "preview"].contains(args[0]) else { die(usage) }
let verb = args[0]
let package = URL(filePath: args[1]).standardizedFileURL
guard package.pathExtension == "icon" else {
    die("\(args[1]) is not an Icon Composer package (<Name>.icon)")
}
let name = package.deletingPathExtension().lastPathComponent
let fm = FileManager.default

// MARK: - the package, checked

let manifest = package.appending(path: "icon.json")
guard let data = fm.contents(atPath: manifest.path),
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
else { die("\(manifest.path) is missing or not JSON") }
let layers = ((json["groups"] as? [[String: Any]]) ?? [])
    .flatMap { ($0["layers"] as? [[String: Any]]) ?? [] }
    .compactMap { $0["image-name"] as? String }
guard !layers.isEmpty else { die("\(manifest.path) names no layers") }
for layer in layers {
    guard layer.hasSuffix(".svg") else {
        die("layer \(layer) is not SVG: the layers are the drawing, as vector")
    }
    let file = package.appending(path: "Assets/\(layer)")
    guard fm.fileExists(atPath: file.path) else {
        die("layer \(layer) is not in \(package.path)/Assets")
    }
    let svg = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    guard !svg.contains("<filter") else {
        die(
            "layer \(layer) uses an SVG filter, which Icon Composer ignores: bake the effect into the geometry"
        )
    }
}

let scratch = fm.temporaryDirectory.appending(path: "mark-\(name)-\(getpid())")
try? fm.removeItem(at: scratch)
do { try fm.createDirectory(at: scratch, withIntermediateDirectories: true) } catch {
    die("create \(scratch.path): \(error.localizedDescription)")
}
defer { try? fm.removeItem(at: scratch) }

// MARK: - build

if verb == "build" {
    guard let outPath = value("--out") else { die(usage) }
    let out = URL(filePath: outPath)
    do { try fm.createDirectory(at: out, withIntermediateDirectories: true) } catch {
        die("create \(out.path): \(error.localizedDescription)")
    }
    run([
        "xcrun", "actool", package.path, "--compile", scratch.path, "--app-icon", name,
        "--target-device", "mac", "--minimum-deployment-target", "26.0", "--platform", "macosx",
        "--standalone-icon-behavior", "all", "--output-format", "human-readable-text",
        "--output-partial-info-plist", scratch.appending(path: "icon.plist").path,
    ])
    for file in ["Assets.car", "\(name).icns"] {
        let dest = out.appending(path: file)
        try? fm.removeItem(at: dest)
        do { try fm.moveItem(at: scratch.appending(path: file), to: dest) } catch {
            die("actool left no \(file): \(error.localizedDescription)")
        }
        print("\(dest.path)")
    }
    if let png = value("--png") {
        let set = scratch.appending(path: "\(name).iconset")
        run([
            "xcrun", "iconutil", "-c", "iconset", out.appending(path: "\(name).icns").path, "-o",
            set.path,
        ])
        let dest = URL(filePath: png)
        try? fm.removeItem(at: dest)
        do { try fm.moveItem(at: set.appending(path: "icon_512x512.png"), to: dest) } catch {
            die("no 512 px rendering in the icns: \(error.localizedDescription)")
        }
        print("\(dest.path)")
    }
    // The bundle names the icon twice: CFBundleIconName finds the glass one
    // in Assets.car, CFBundleIconFile the icns fallback.
    print("Info.plist: CFBundleIconName = \(name), CFBundleIconFile = \(name)")
    exit(0)
}

// MARK: - preview

let developer = run(["xcode-select", "-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
let ictool = URL(filePath: developer)
    .deletingLastPathComponent()
    .appending(path: "Applications/Icon Composer.app/Contents/Executables/ictool").path
guard fm.isExecutableFile(atPath: ictool) else {
    die("no ictool at \(ictool): it ships with Xcode 26+")
}

let appearances =
    args.contains("--all")
    ? ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"] : ["Default"]
var rows = ""
for appearance in appearances {
    let png = scratch.appending(path: "\(appearance).png")
    run([
        ictool, package.path, "--export-image", "--output-file", png.path, "--platform", "macOS",
        "--rendition", appearance, "--width", "1024", "--height", "1024", "--scale", "1",
    ])
    guard let image = fm.contents(atPath: png.path) else { die("ictool drew no \(appearance)") }
    let src = "data:image/png;base64,\(image.base64EncodedString())"
    let sizes = [256, 128, 64, 32, 20]
        .map { "<img src=\"\(src)\" width=\"\($0)\" height=\"\($0)\">" }.joined()
    rows +=
        "<div><div class=\"label\">\(name) · \(appearance)</div><div class=\"sizes\">\(sizes)</div></div>"
}
let page = """
    <!doctype html><meta charset="utf-8"><title>\(name) · mark preview</title>
    <style>
    body { margin: 0; font: 13px ui-monospace, monospace }
    .panel { padding: 32px; display: flex; flex-direction: column; gap: 24px }
    .label { opacity: .6 }
    .sizes { display: flex; gap: 24px; align-items: flex-end; margin-top: 8px }
    </style>
    <div class="panel" style="background:#262626;color:#ddd">\(rows)</div>
    <div class="panel" style="background:#f2f2f2;color:#222">\(rows)</div>
    """
let out = fm.temporaryDirectory.appending(path: "mark-preview-\(name).html")
do { try page.write(to: out, atomically: true, encoding: .utf8) } catch {
    die("write \(out.path): \(error.localizedDescription)")
}
run(["open", out.path])
print(out.path)
