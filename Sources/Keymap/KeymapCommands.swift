import SwiftUI

/// One native menu over registry sections: each action a real menu item
/// carrying its LIVE key (the first local combo), searchable via the Help
/// menu like any native command. Alternates beyond the representative ride
/// `LocalKeyRouter`. Compose into the app's `.commands { }`.
public struct KeymapMenu<A: ActionSet>: Commands {
    let title: String
    let sections: [ActionSection<A>]
    let store: KeymapStore<A>
    let isEnabled: (A) -> Bool
    let perform: (A) -> Void

    public init(
        title: String,
        sections: [ActionSection<A>] = A.sections,
        store: KeymapStore<A>,
        isEnabled: @escaping (A) -> Bool = { _ in true },
        perform: @escaping (A) -> Void
    ) {
        self.title = title
        self.sections = sections
        self.store = store
        self.isEnabled = isEnabled
        self.perform = perform
    }

    public var body: some Commands {
        CommandMenu(title) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                if index > 0 { Divider() }
                ForEach(section.actions, id: \.self) { action in
                    let item = Button {
                        perform(action)
                    } label: {
                        Label(action.spec.title, systemImage: action.spec.symbol)
                    }
                    .disabled(!isEnabled(action))
                    if let shortcut = store.menuShortcut(for: action) {
                        item.keyboardShortcut(shortcut)
                    } else {
                        item
                    }
                }
            }
        }
    }
}
