import Ink
import PermissionGrants
import SwiftUI

// PermissionGrants' shapes over real permissions: `mise run grant-example`
// builds and opens a signed app with its own bundle id, so every answer is
// macOS's for this app and every ask is the real one. One set of grants drawn
// as a Settings section, one sheet, steps (a page per grant) and inline chips;
// pick a shape at the top. `--render <dir>` writes each shape as a PNG.

// The app's permissions, each declared once: these names are every screen's
// rows and every line of code's gates.
extension PermissionGrant {
    static let microphone = PermissionGrant.privacy(
        .microphone, title: "Microphone", why: "Hears what you say.", required: false)
    static let keyLight = PermissionGrant.privacy(
        .inputMonitoring, title: "Input Monitoring", why: "Lights Caps Lock while the mic is open.",
        required: false)
    static let typing = PermissionGrant.privacy(
        .postEvents, title: "Accessibility", why: "Types into other apps.", required: false)
    static let speech = PermissionGrant.privacy(
        .speechRecognition, title: "Speech Recognition", why: "Turns what you say into text.",
        required: false)
    static let headMotion = PermissionGrant.privacy(
        .motion, title: "Head gestures", why: "A nod says yes, a shake says no.", required: false)
    /// The helper's person-facing side.
    static let helper = PermissionGrant.backgroundService(
        .helper, title: "Background helper", why: "Keeps running when the window is closed.")
}

extension AppInstallation.Job {
    /// The bundled launch agent: the same binary idling with `--helper`.
    /// launchd is asked whether it runs (no probe of its own).
    static let helper = AppInstallation.Job(
        .agent(plist: "garden.untitled.grant-example.helper.plist"), name: "the helper")
}

let grants: [PermissionGrant] = [
    .microphone, .keyLight, .typing, .speech, .headMotion, .helper,
]

enum Shape: String, CaseIterable { case section, sheet, steps, chip }

/// The ground truth for "Posting events": opens a fresh empty document in
/// TextEdit and posts "granted" to it as keystrokes. Whether the word appears
/// is what macOS lets THIS process do, whatever any check answers.
@MainActor func typeTestWord() {
    let document = URL(filePath: NSTemporaryDirectory()).appending(
        path: "grant-example-\(Int(Date().timeIntervalSince1970)).txt")
    FileManager.default.createFile(atPath: document.path, contents: Data())
    let textEdit = URL(filePath: "/System/Applications/TextEdit.app")
    Task {
        let app: NSRunningApplication
        do {
            app = try await NSWorkspace.shared.open(
                [document], withApplicationAt: textEdit, configuration: .init())
        } catch {
            print("type test word: TextEdit did not open: \(error)")
            return
        }
        // The document's window takes the keys once TextEdit is in front.
        for _ in 0..<50 where !app.isActive { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(300))
        let source = CGEventSource(stateID: .privateState)
        let word = Array("granted".utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.flags = []
            event?.keyboardSetUnicodeString(stringLength: word.count, unicodeString: word)
            event?.postToPid(app.processIdentifier)
        }
        print("typed test word into TextEdit; the grant reads \(PermissionGrant.typing.standing)")
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
        let reads = PermissionGrant.keyLight.isAllowed ? "allowed" : "not allowed"
        result = tap == nil ? "listen: REFUSED (reads \(reads))" : "listen: WORKS (reads \(reads))"
        if let tap { CFMachPortInvalidate(tap) }
        print(result)
    }
}

struct Gallery: View {
    /// `--shape chip` opens on that tab.
    @State private var shape: Shape = {
        let args = CommandLine.arguments
        guard let at = args.firstIndex(of: "--shape"), at + 1 < args.count,
            let shape = Shape(rawValue: args[at + 1])
        else { return .section }
        return shape
    }()
    /// The whole window on one material: flip it to see every control change.
    @State private var material = InkMaterial.glass

    var body: some View {
        VStack(spacing: 0) {
            InkTabs($shape, Shape.allCases.map { InkTab($0.rawValue, $0) }).padding(12)
            Divider()
            view(shape).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            HStack(spacing: 8) {
                InkTabs(
                    $material, [InkTab("glass", InkMaterial.glass), InkTab("flat", .flat)],
                    size: .small)
                Spacer()
                Text(ListenTest.shared.result).font(.caption.monospaced())
                Button("listen test") { ListenTest.shared.run() }
                Button("type a test word") { typeTestWord() }
                Button("turn the helper off") { PermissionGrant.helper.unregister() }
            }
            .buttonStyle(.ink)
            .padding(10)
        }
        .inkMaterial(material)
        .frame(width: 600, height: 620)
    }
}

@MainActor @ViewBuilder func view(_ shape: Shape, rendering: Bool = false) -> some View {
    switch shape {
    case .section:
        // ImageRenderer draws no Form: the render shows the section bare.
        if rendering {
            PermissionGrant.Section(
                "Permissions", grants, footer: "Rows read live; nothing here holds state."
            )
            .padding(20)
        } else {
            Form {
                Section("Permissions") {
                    PermissionGrant.Section(
                        grants, footer: "Rows read live; nothing here holds state.")
                }
            }
            .formStyle(.grouped)
        }
    case .sheet:
        PermissionGrant.Sheet(
            title: "quick setup", subtitle: "one grant to start, the rest optional.", grants,
            optionalNote: "Without them the example still runs; it just does less."
        ) {}
    case .steps:
        PermissionGrant.Steps(grants) {
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
            Text("The warning is the button: hover says the fix. Nothing once it is good.")
                .font(.caption).foregroundStyle(.secondary)
            // A menu's row: the width the menu gives it, in the app's voice.
            PermissionGrant.Chip(.typing, label: "can't type into apps yet", fill: true)
                .permissionGrantCase(.lower)
            PermissionGrant.Chip(.speech, label: "can't turn speech into text yet", fill: true)
                .permissionGrantCase(.lower)
            // Inline: hugging its words, in macOS's case.
            HStack(spacing: 8) {
                PermissionGrant.Chip(.keyLight, label: "Caps Lock light")
                PermissionGrant.Chip(.headMotion)
            }
        }
        .padding(20)
    }
}

struct GrantExample: App {
    var body: some Scene {
        // One window, the app's whole life: closing it quits, so the bundle
        // is free to drag to the Trash (Finder refuses an app still running).
        Window("grant shapes", id: "gallery") {
            Gallery().onAppear {
                NSApp.activate()
                // The hook, the way an app reacts to a change without a loop.
                for grant in grants {
                    grant.observe { print("\(grant.title) changed to \($0)") }
                }
            }
        }
        .windowResizability(.contentSize)
    }
}

// First thing: a probe launch answers the hub and exits.
PermissionGrant.answerProbeIfAsked()

let args = CommandLine.arguments
if args.contains("--reset-helper") {
    // Back to square one for the helper's flow (run from the installed copy).
    PermissionGrant.helper.unregister()
    print("helper unregistered")
} else if args.contains("--helper") {
    // The launch agent: alive, doing nothing, until launchd stops it. Its app
    // deleted, it leaves launchd; its app upgraded, KeepAlive restarts it
    // into the new image.
    let watch = AppInstallation.ImageWatch.start(goneAfter: 3) {}
    withExtendedLifetime(watch) { dispatchMain() }
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
    // Deleted while open: it tries to unregister the helper (macOS may refuse
    // with the bundle gone; the helper then boots itself out), then quits.
    // Upgraded: it reopens into the new build.
    let watch = AppInstallation.ImageWatch.start {
        try? AppInstallation.Job.helper.uninstall()
    }
    NSApplication.shared.setActivationPolicy(.regular)
    withExtendedLifetime(watch) { GrantExample.main() }
}
