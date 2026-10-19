import AppKit
import Ink
import SwiftUI

// The Ink text demo: `swift run ink-example`. MiddleTruncate against SwiftUI's own
// two cuts, one width slider moving all three at once (one thing varied); then Copy
// on values in a row and in a sentence; then CopyableCommand. All data invented.

let wallets = [
    ("savings", "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"),
    ("trading", "0x71C7656EC7ab88b098defB751B7401B5f6d8A21c"),
    ("cold", "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"),
]

struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: .inkLane) {
            Text(title).planeHeaderStyle()
            content
        }
    }
}

struct Toolbar: View {
    var pinBelow = false
    private let tools = [
        ("play.fill", "play"), ("backward.fill", "back 10 seconds"),
        ("forward.fill", "forward 10 seconds"), ("speaker.wave.2.fill", "volume"),
        ("captions.bubble", "captions: off. Press c to cycle them."),
    ]

    var body: some View {
        HStack(spacing: .inkBlock) {
            ForEach(Array(tools.enumerated()), id: \.offset) { i, tool in
                Button {
                } label: {
                    Image(systemName: tool.0).font(.title3).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .inkTip(tool.1, edge: pinBelow && i == tools.count - 1 ? .bottom : nil)
            }
        }
    }
}

struct DemoView: View {
    @State private var width: CGFloat = 200
    @State private var secret = ""
    @State private var newSecret = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Section(title: "the end tells them apart") {
                    HStack {
                        Text("width").foregroundStyle(.secondary)
                        Slider(value: $width, in: 60...420)
                        Text("\(Int(width)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 520)
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                        GridRow {
                            Text(".tail").foregroundStyle(.secondary)
                            Text(".middle").foregroundStyle(.secondary)
                            Text("MiddleTruncate(tail: 6)").foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        ForEach(wallets, id: \.1) { _, address in
                            GridRow {
                                Text(address).lineLimit(1).truncationMode(.tail).frame(
                                    width: width, alignment: .leading)
                                Text(address).lineLimit(1).truncationMode(.middle).frame(
                                    width: width, alignment: .leading)
                                MiddleTruncate(address, tail: 6).frame(
                                    width: width, alignment: .leading)
                            }
                        }
                    }
                    .font(.body.monospaced())
                }

                Section(title: "a separator keeps what follows it") {
                    VStack(alignment: .leading, spacing: 6) {
                        MiddleTruncate(
                            "/Users/someone/Projects/garden/assets/photos/2025/greenhouse-tomatoes.jpg",
                            tail: "/")
                        MiddleTruncate(
                            "quarterly-report-for-the-board-meeting-second-draft.pdf", tail: ".")
                        MiddleTruncate(
                            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                            tail: 6)
                    }
                    .font(.body.monospaced())
                    .frame(width: width, alignment: .leading)
                }

                Section(title: "the text is the button") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(wallets, id: \.1) { name, address in
                            HStack(alignment: .firstTextBaseline, spacing: .inkLane) {
                                Text(name).foregroundStyle(.secondary).frame(
                                    width: 56, alignment: .leading)
                                Copy(address) { MiddleTruncate(address, tail: 6) }
                                    .font(.callout.monospaced())
                            }
                        }
                    }
                    .frame(width: width + 70, alignment: .leading)
                    HStack(spacing: 4) {
                        Text("order")
                        Copy("A7K-29Q4") { Text(verbatim: "A7K-29Q4") }.font(.body.monospaced())
                        Text("has shipped")
                    }
                }

                // One thing varies down the rows: who speaks on the hover. One tip,
                // always: a Copy's tip silences the cut text's own.
                Section(title: "one hover, one tooltip") {
                    let address = wallets[0].1
                    Grid(alignment: .leading, horizontalSpacing: .inkLane, verticalSpacing: 8) {
                        GridRow {
                            Text("no tip").foregroundStyle(.secondary)
                            Copy(address) { MiddleTruncate(address, tail: 6) }
                                .frame(width: width, alignment: .leading)
                            Text("the whole address, only when cut").foregroundStyle(.tertiary)
                        }
                        GridRow {
                            Text("tip: address").foregroundStyle(.secondary)
                            Copy(address, tip: address) { MiddleTruncate(address, tail: 6) }
                                .frame(width: width, alignment: .leading)
                            Text("the whole address, always").foregroundStyle(.tertiary)
                        }
                        GridRow {
                            Text("tip: words").foregroundStyle(.secondary)
                            Copy(address, tip: "Copy the savings address") {
                                MiddleTruncate(address, tail: 6)
                            }
                            .frame(width: width, alignment: .leading)
                            Text("yours, and only yours").foregroundStyle(.tertiary)
                        }
                        GridRow {
                            Text("tip: sentences").foregroundStyle(.secondary)
                            Copy(
                                address,
                                tip:
                                    "Copies the savings address, e.g. for a transfer. Exactly as stored, never retyped."
                            ) {
                                MiddleTruncate(address, tail: 6)
                            }
                            .frame(width: width, alignment: .leading)
                            Text("one sentence per line, e.g. kept whole").foregroundStyle(
                                .tertiary)
                        }
                        GridRow {
                            Text("the mark alone").foregroundStyle(.secondary)
                            HStack(spacing: .inkGap) {
                                MiddleTruncate(address, tail: 6)
                                Copy(address, tip: "Copy")
                            }
                            .frame(width: width + 30, alignment: .leading)
                            Text("beside a value already shown").foregroundStyle(.tertiary)
                        }
                    }
                    .font(.callout.monospaced())
                }

                Section(title: "a command on its own") {
                    CopyableCommand(
                        "curl -fsSL https://example.com/install.sh | bash -s -- --prefix ~/.local --channel stable"
                    )
                    .frame(maxWidth: width + 160, alignment: .leading)
                }

                // Sweep the pointer along a row: the first tip waits a beat, the
                // next ones follow at once; a click puts the tip away. The second
                // row wears the bubble (HUD and media chrome), above its glyph;
                // the last glyph pins its tip below.
                Section(title: "a toolbar's tips") {
                    Toolbar()
                    Toolbar(pinBelow: true)
                        .padding(10)
                        .background(.black.opacity(0.55), in: Capsule())
                        .inkTipStyle(.bubble)
                }

                // Secrets, composed: typed into SecretField; shown as Veiled (a
                // click peeks it five seconds); copied beside it without being
                // shown (Copy, the mark alone). Siblings, never nested: a click
                // on the value peeks, a click on the mark copies.
                Section(title: "secrets") {
                    SecretField(prompt: "password", text: $secret)
                        .frame(width: 280)
                    SecretField(
                        prompt: "new password, 12 or more", text: $newSecret,
                        contentType: .newPassword, valid: newSecret.count >= 12
                    )
                    .frame(width: 280)
                    HStack(spacing: .inkGap) {
                        Text("serial").foregroundStyle(.secondary)
                        Veiled("C02XK1ABJG5H")
                        Copy("C02XK1ABJG5H", tip: "Copy without showing it")
                    }
                    .font(.callout)
                }

                // The one keycap: a key alone, a combo, beside a label, on a
                // prominent button, held.
                Section(title: "keys") {
                    HStack(spacing: .inkGap) {
                        InkKey("esc")
                        InkKey("↩")
                        InkKey("⌘K")
                        InkKey("⌥⌘1")
                        InkKey("⇧⌘P")
                        InkKey("⇪", lit: true)
                    }
                    HStack(spacing: .inkBlock) {
                        HStack(spacing: 6) {
                            Text("Open palette").foregroundStyle(.secondary)
                            InkKey("⌘K")
                        }
                        Button {
                        } label: {
                            InkKeyed("Submit", key: "↩", on: .prominent)
                        }
                        .buttonStyle(.inkProminent)
                        InkCloseButton {}
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

struct DemoApp: App {
    var body: some Scene {
        WindowGroup("ink demo") {
            DemoView()
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}

// A bare SPM executable is a .prohibited-policy process: its window exists
// but the app cannot be activated or brought forward. Declare regular.
NSApplication.shared.setActivationPolicy(.regular)
DemoApp.main()
