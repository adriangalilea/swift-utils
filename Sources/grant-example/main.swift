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
    .agent(plist: "garden.untitled.grant-example.helper.plist"), title: "the helper",
    why: "Keeps working while the window is closed.")
let grants: [any Grant] = [
    TCCGrant(.microphone, title: "Microphone", why: "Hears what you say.", required: false),
    TCCGrant(
        .inputMonitoring, title: "Input Monitoring", why: "Lights Caps Lock while the mic is open.",
        required: false, withoutIt: "The key works; its light stays off."),
    TCCGrant(
        .postEvents, title: "Accessibility", why: "Types into other apps.", required: false,
        withoutIt: "It can show text, never type it."),
    helper,
]

enum Shape: String, CaseIterable { case section, sheet, steps, chip }

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

let args = CommandLine.arguments
if args.contains("--helper") {
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
