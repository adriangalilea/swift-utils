import AppIntents
import Foundation

/// App Intents is the macOS command palette: conforming the registry puts
/// every action in Spotlight, Siri, Shortcuts, and Apple Intelligence for
/// free - which is why Keymap ships no palette of its own.
///
/// The framework extracts intent metadata at compile time from CONCRETE
/// types in the app target, so no library can vend the intent itself. What
/// the library CAN own, it does: conform your action enum to
/// `KeymapAppEnum` (one empty extension - display names derive from specs),
/// then the app writes its one concrete intent, genesis-templated:
///
/// ```swift
/// extension Act: KeymapAppEnum {
///     static let typeDisplayRepresentation: TypeDisplayRepresentation = "Action"
/// }
///
/// struct PerformAction: AppIntent {
///     static let title: LocalizedStringResource = "Perform Action"
///     @Parameter(title: "Action") var action: Act
///     @MainActor func perform() async throws -> some IntentResult {
///         AppModel.shared.perform(action)
///         return .result()
///     }
/// }
/// ```
///
/// If the per-app stub ever grows past this, the escalation is a macro that
/// generates it - not more protocol machinery.
public protocol KeymapAppEnum: ActionSet, AppEnum {}

extension KeymapAppEnum {
    /// Display names derive from the registry, so Spotlight/Shortcuts naming
    /// can never drift from the app's own.
    public static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        Dictionary(uniqueKeysWithValues: allCases.map { action in
            (action, DisplayRepresentation(
                title: LocalizedStringResource(stringLiteral: action.spec.title),
                image: .init(systemName: action.spec.symbol)
            ))
        })
    }
}
