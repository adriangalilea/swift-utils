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
    /// Checks every intent display title against the registry title.
    /// `precondition`, deliberately: dev builds are Release-config in this
    /// house, so `assert` would never run anywhere - and because both sides
    /// resolve the same catalog KEY, an English match implies every
    /// language matches, making the crash impossible to ship past the first
    /// launch that could reveal it.
    @MainActor public static func assertIntentDisplayMatchesRegistry() {
        for action in allCases {
            guard let representation = caseDisplayRepresentations[action] else {
                preconditionFailure("intent display missing for \(action.rawValue)")
            }
            let intentTitle = String(localized: representation.title)
            precondition(
                intentTitle == action.spec.title,
                "intent display '\(intentTitle)' drifted from registry title '\(action.spec.title)' for \(action.rawValue)"
            )
        }
    }
}
