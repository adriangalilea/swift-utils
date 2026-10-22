import Foundation
import Keymap
import SwiftUI

// The laws, over the registry the window draws: every one is printed, every
// violation is listed, and any violation exits 1. Reveals come from a real
// RevealMonitor, so the reveal each state derives is checked with them.

@MainActor private var failures: [String] = []

@MainActor private func law(_ name: String, _ holds: Bool, _ detail: @autoclosure () -> String = "")
{
    print((holds ? "ok    " : "FAIL  ") + name)
    if !holds { failures.append(name + (detail().isEmpty ? "" : ": " + detail())) }
}

@MainActor func runChecks() -> Never {
    let suite = "keymap-example.check"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = KeymapStore<Command>(defaults: defaults)
    let monitor = RevealMonitor()
    monitor.appActive = true

    func shown(_ chords: [ShortcutChord], configure: (RevealMonitor) -> Void) -> [String] {
        monitor.flags = []
        monitor.bareReveal = false
        monitor.globalReveal = false
        monitor.suppressed = false
        configure(monitor)
        return shortcutCompletions(chords, monitor.reveal!)
    }
    let play = store.chords(for: .play) + [playMediaKey]
    let search = store.chords(for: .search)
    let favorite = store.chords(for: .favorite)

    // ---- completions: the minimal form per prefix ----
    let bareSearch = shown(search) { $0.bareReveal = true }
    law("the bare reveal shows search's bare form", bareSearch == ["/"], "\(bareSearch)")
    let commandSearch = shown(search) { $0.flags = .command }
    law("⌘ shows search's ⌘ form", commandSearch == ["⌘F"], "\(commandSearch)")
    let barePlay = shown(play) { $0.bareReveal = true }
    law("the bare reveal shows play's one bare form", barePlay == ["Space"], "\(barePlay)")
    let controlPlay = shown(play) { $0.flags = .control }
    law("⌃ completes play to its global chord", controlPlay == ["⌃⌥⌘P"], "\(controlPlay)")

    // ---- completions: globals-only shows every global form, fewest modifiers first ----
    let globalPlay = shown(play) { $0.globalReveal = true }
    law("the global reveal shows every global form", globalPlay == ["⏯", "⌃⌥⌘P"], "\(globalPlay)")
    let doubled = shown(play + [playMediaKey]) { $0.globalReveal = true }
    law("a form is listed once", doubled == ["⏯", "⌃⌥⌘P"], "\(doubled)")

    // ---- completions: empty when unreachable ----
    let optionFavorite = shown(favorite) { $0.flags = .option }
    law("⌥ cannot reach ⌘D", optionFavorite.isEmpty, "\(optionFavorite)")
    let globalFavorite = shown(favorite) { $0.globalReveal = true }
    law("an in-app-only action has no global form", globalFavorite.isEmpty, "\(globalFavorite)")
    let inactiveFavorite = shown(favorite) {
        $0.appActive = false
        $0.flags = .command
    }
    monitor.appActive = true
    law("an inactive app reaches no in-app chord", inactiveFavorite.isEmpty, "\(inactiveFavorite)")
    monitor.bareReveal = true
    monitor.suppressed = true
    law("a modal silences every reveal", monitor.reveal == nil)

    // ---- placement: beside the anchor on its edge, the other side when there is no room ----
    let bounds = CGSize(width: 760, height: 480)
    let size = CGSize(width: 80, height: 22)
    func tip(_ anchor: CGRect, _ edge: Edge) -> CGRect {
        let p = ShortcutTip.place(anchor: anchor, size: size, edge: edge, bounds: bounds)
        return CGRect(
            x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width,
            height: size.height)
    }
    let control = CGSize(width: 28, height: 28)
    let middle = CGRect(origin: CGPoint(x: 366, y: 226), size: control)
    let atTop = CGRect(origin: CGPoint(x: 366, y: 8), size: control)
    let atBottom = CGRect(origin: CGPoint(x: 366, y: 480 - 8 - 28), size: control)
    let atLeading = CGRect(origin: CGPoint(x: 8, y: 226), size: control)
    let atTrailing = CGRect(origin: CGPoint(x: 760 - 8 - 28, y: 226), size: control)
    let cases: [(String, CGRect, Edge, (CGRect, CGRect) -> Bool)] = [
        ("a top tip with room lands above", middle, .top, { $0.midY < $1.midY }),
        ("a top-edge control's tip lands below", atTop, .top, { $0.midY > $1.midY }),
        ("a bottom tip with room lands below", middle, .bottom, { $0.midY > $1.midY }),
        ("a bottom-edge control's tip lands above", atBottom, .bottom, { $0.midY < $1.midY }),
        ("a leading tip with room lands before", middle, .leading, { $0.midX < $1.midX }),
        ("a leading-edge control's tip lands after", atLeading, .leading, { $0.midX > $1.midX }),
        ("a trailing tip with room lands after", middle, .trailing, { $0.midX > $1.midX }),
        (
            "a trailing-edge control's tip lands before", atTrailing, .trailing,
            { $0.midX < $1.midX }
        ),
    ]
    let layer = CGRect(origin: .zero, size: bounds)
    for (name, anchor, edge, side) in cases {
        let placed = tip(anchor, edge)
        law(name, side(placed, anchor), "tip \(placed), anchor \(anchor)")
        law("\(name), clear of its anchor", !placed.intersects(anchor), "tip \(placed)")
        law("\(name), inside the layer", layer.contains(placed), "tip \(placed)")
    }
    let corner = CGRect(x: 0, y: 200, width: 12, height: 12)
    let clamped = tip(corner, .top)
    law(
        "a tip above a control at the left edge keeps 8pt of margin", clamped.minX >= 8,
        "\(clamped)")

    guard failures.isEmpty else {
        FileHandle.standardError.write(
            Data(
                ("keymap-example check FAILED:\n"
                    + failures.map { "  " + $0 }.joined(separator: "\n")
                    + "\n").utf8))
        exit(1)
    }
    print("keymap-example: every law holds")
    exit(0)
}
