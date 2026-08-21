import Foundation

/// The ONE user-facing answer for a grant, presentation riding the state.
///
/// THE LAW this type exists to enforce: a surface renders a Standing
/// mechanically (grade → checkmark or button, `actionTitle` on the button,
/// `note` under the why) and NEVER re-derives "is this a problem?" from
/// anything rawer. Two surfaces answering that question with their own
/// thresholds is the split-brain bug - Settings warning while the main
/// window shrugs - and with Standing as the only readable vocabulary it
/// is unwritable.
public struct Standing: Equatable, Sendable {
    public enum Grade: Equatable, Sendable {
        /// Nothing to do. Checkmark; no surface warns, no banner, no note.
        case good
        /// Not yet granted, one click asks. An OFFER, never a failure:
        /// onboarding and settings present it, nothing warns about it.
        case askable
        /// The user must fix something outside the app. EVERY surface
        /// warns - row, banner, preflight - with this same note + action.
        case broken
    }

    public let grade: Grade
    public let actionTitle: String
    public let note: String?

    public static let good = Standing(grade: .good, actionTitle: "", note: nil)

    public static func askable(_ actionTitle: String, note: String? = nil) -> Standing {
        Standing(grade: .askable, actionTitle: actionTitle, note: note)
    }

    /// Broken always carries its fix: a note is required by construction.
    public static func broken(_ actionTitle: String, note: String) -> Standing {
        Standing(grade: .broken, actionTitle: actionTitle, note: note)
    }
}

/// Anything the app needs the user or system to allow: a TCC grant, a
/// system-extension enable, a capability claim. The app defines each
/// grant ONCE - identity copy, the standing derivation, the action - and
/// every surface consumes that one definition.
public protocol Grant {
    var symbol: String { get }
    var title: String { get }
    var why: String { get }
    /// Required gates a feature; optional only enriches one. Drives
    /// `blocking` and how onboarding groups the rows.
    var required: Bool { get }
    /// Derived fresh on every read - the one place raw status becomes
    /// presentation. Reading observable state here is what keeps every
    /// rendering surface live.
    var standing: Standing { get }
    /// The standing's action: fire the prompt, or open the right Settings.
    func act()
}

extension Grant {
    /// THE banner/preflight predicate, defined once: a required grant the
    /// user must fix. Optional grants never block anything.
    public var blocking: Bool { required && standing.grade == .broken }
}
