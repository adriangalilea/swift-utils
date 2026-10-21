import Grant
import SwiftUI

// The Grant shapes over real permissions: `mise run grant-example` builds and
// opens a signed app with its own bundle id, so every answer is macOS's for
// this app and every ask is the real one. One set of grants drawn as a Settings
// section, one sheet, steps (a page per grant) and inline chips; pick a shape at
// the top. `--render <dir>` writes each shape as a PNG.

/// The bundled launch agent (`mise run grant-example` builds the app that
/// carries it): the same binary idling with `--helper`. Declared before
/// `grants`: main.swift initializes top-level constants in order, and one
/// read before its line is an uninitialized value (an empty plist name that
/// crashed SMAppService.status).
let helper = BackgroundServiceGrant(
    .agent(plist: "garden.untitled.grant-example.helper.plist"), title: "Background helper",
    why: "Keeps running when the window is closed.")
let grants: [any Grant] = [
    TCCGrant(.microphone, title: "Microphone", why: "Hears what you say.", required: false),
    TCCGrant(
        .inputMonitoring, title: "Input Monitoring", why: "Lights Caps Lock while the mic is open.",
        required: false),
    TCCGrant(.postEvents, title: "Accessibility", why: "Types into other apps.", required: false),
    helper,
]

enum Shape: String, CaseIterable { case section, sheet, steps, chip }

/// The ground truth for "Posting events": 3 s after the press (time to click
/// into a text field in another app) this process posts "granted" as
/// keystrokes. Whether the word appears is what macOS lets THIS process do,
/// whatever any check answers.
@MainActor func typeTestWord() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        let source = CGEventSource(stateID: .privateState)
        let word = Array("granted".utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.flags = []
            event?.keyboardSetUnicodeString(stringLength: word.count, unicodeString: word)
            event?.post(tap: .cghidEventTap)
        }
        print("typed test word; hub reads \(Permissions.shared.answer(.postEvents).rawValue)")
    }
}

/// The ground truth for Input Monitoring: may THIS process watch the keyboard
/// right now? A listen-only event tap is refused (nil) without it.
@Observable @MainActor final class ListenTest {
    static let shared = ListenTest()
    var result = ""
    func run() {
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil)
        let hub = Permissions.shared.answer(.inputMonitoring).rawValue
        result = tap == nil ? "listen: REFUSED (hub: \(hub))" : "listen: WORKS (hub: \(hub))"
        if let tap { CFMachPortInvalidate(tap) }
        print(result)
    }
}

struct Gallery: View {
    @State private var shape = Shape.section
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $shape) {
                ForEach(Shape.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(12)
            Divider()
            view(shape).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            HStack {
                Text("replay: `grant reset grant-example` clears the permissions")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Text(ListenTest.shared.result).font(.caption.monospaced())
                Button("listen test") { ListenTest.shared.run() }.controlSize(.small)
                Button("type a test word") { typeTestWord() }.controlSize(.small)
                Button("turn the helper off") { helper.unregister() }.controlSize(.small)
            }
            .padding(10)
        }
        .frame(width: 520, height: 440)
    }
}

@MainActor @ViewBuilder func view(_ shape: Shape, rendering: Bool = false) -> some View {
    switch shape {
    case .section:
        // ImageRenderer draws no Form: the render shows the section bare.
        if rendering {
            GrantSection("Permissions", grants, footer: "Rows read live; nothing here holds state.")
                .padding(20)
        } else {
            Form {
                Section("Permissions") {
                    GrantSection(grants, footer: "Rows read live; nothing here holds state.")
                }
            }
            .formStyle(.grouped)
        }
    case .sheet:
        GrantSheet(
            title: "quick setup", subtitle: "one grant to start, three optional.", grants,
            optionalNote: "Without them the example still runs; it just does less."
        ) {}
    case .steps:
        GrantSteps(grants) {
            VStack(spacing: 12) {
                Image(systemName: "hand.wave").font(.system(size: 48)).foregroundStyle(.secondary)
                Text("Welcome").font(.title.bold())
                Text("A page per grant. Each moves on by itself once its grant is good.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(
                        maxWidth: 340)
            }
        } onDone: {
        }
    case .chip:
        VStack(alignment: .leading, spacing: 10) {
            Text("Inline: only what needs the person, nothing once it is good.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(grants.enumerated()), id: \.offset) { _, grant in GrantChip(grant) }
        }
        .padding(20)
    }
}

struct GrantExample: App {
    var body: some Scene {
        WindowGroup("grant shapes") {
            Gallery().onAppear { NSApp.activate() }
        }
        .windowResizability(.contentSize)
    }
}

// First thing: a probe launch answers the hub and exits.
Permissions.answerProbeIfAsked()

let args = CommandLine.arguments
if args.contains("--reset-helper") {
    // Back to square one for the helper's flow (run from the installed copy).
    helper.unregister()
    print("helper unregistered")
} else if args.contains("--helper") {
    // The launch agent: alive, doing nothing, until launchd stops it.
    dispatchMain()
} else if let at = args.firstIndex(of: "--render"), at + 1 < args.count {
    let dir = URL(fileURLWithPath: args[at + 1])
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for shape in Shape.allCases {
        MainActor.assumeIsolated {
            let renderer = ImageRenderer(
                content: view(shape, rendering: true).frame(width: 520, height: 400)
                    .background(Color(nsColor: .windowBackgroundColor)).environment(
                        \.colorScheme, .dark))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { preconditionFailure("render \(shape) failed") }
            try? png.write(to: dir.appending(path: "\(shape.rawValue).png"))
        }
    }
    print("rendered \(Shape.allCases.count) shapes to \(dir.path)")
} else {
    NSApplication.shared.setActivationPolicy(.regular)
    GrantExample.main()
}
