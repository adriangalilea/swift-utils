import AppIntents
import Foundation

/// App Intents is the macOS command palette: exposing the registry puts
/// every action in Spotlight, Siri, Shortcuts, and Apple Intelligence -
/// which is why Keymap ships no palette of its own.
///
/// The library CANNOT own the conformance, proven empirically: the
/// metadata extractor demands a COMPILE-TIME LITERAL
/// `caseDisplayRepresentations` dictionary in the app target ("a
/// compile-time static value must be provided" - a protocol-extension
/// derivation halts the build), and the intent itself can't be generic
/// over your enum. So the app writes both, genesis-templated:
///
/// ```swift
/// extension Act: AppEnum {
///     static let typeDisplayRepresentation: TypeDisplayRepresentation = "Action"
///     static let caseDisplayRepresentations: [Act: DisplayRepresentation] = [
///         .playPause: "Play/Pause",   // literal duplicates of spec titles,
///         .search: "Search",          // the extractor's price
///     ]
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
/// The duplication the extractor forces is guarded by the screamer below -
/// call it once at startup and the duplicate can never silently drift.
extension ActionSet where Self: AppEnum {
    /// Asserts every intent display title against the registry title (both
    /// resolve through the app's own catalog, so equal keys are equal
    /// strings). Free in Release; the first dev launch screams on drift.
    @MainActor public static func assertIntentDisplayMatchesRegistry() {
        for action in allCases {
            guard let representation = caseDisplayRepresentations[action] else {
                assertionFailure("intent display missing for \(action.rawValue)")
                continue
            }
            let intentTitle = String(localized: representation.title)
            assert(
                intentTitle == action.spec.title,
                "intent display '\(intentTitle)' drifted from registry title '\(action.spec.title)' for \(action.rawValue)"
            )
        }
    }
}
