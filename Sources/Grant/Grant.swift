import Foundation

/// The ONE user-facing answer for a grant, presentation riding the state.
///
/// THE LAW this type exists to enforce: a surface renders a Standing
/// mechanically (grade → checkmark or button, `actionTitle` on the button,
/// `note` under the why) and NEVER re-derives "is this a problem?" from
/// anything rawer. Two surfaces answering that question with their own
/// thresholds is the split-brain bug - Settings warning while the main
/// window shrugs - and with Standing as the only readable vocabulary it
/// is unwritable. An enum so the invalid states (a good with an action,
/// a broken without its fix) are unrepresentable.
public enum Standing: Equatable, Sendable {
    /// Granted, and the app can SEE that it is. Checkmark; no surface
    /// warns, no banner, no note.
    case good
    /// Not yet granted, one click asks. An OFFER, never a failure:
    /// onboarding and settings present it, nothing warns about it.
    case askable(_ actionTitle: String, note: String? = nil)
    /// The user must fix something outside the app. EVERY surface warns -
    /// row, banner, preflight - with this same note + action.
    case broken(_ actionTitle: String, note: String)
    /// The app CANNOT READ whether this is granted (the system hides the
    /// readout from apps), and nothing has contradicted it. Rendered as
    /// exactly that: a quiet "unknown" mark, no checkmark, no button, the
    /// note saying why. Never warns, never blocks, never asks - a
    /// checkmark here would be a lie, a warning would be one too.
    case unknown(note: String)

    /// The payload-free shape, for the comparisons surfaces live on
    /// (`grade == .broken`, `grade.needsUser`).
    public enum Grade: Equatable, Sendable {
        case good, askable, broken, unknown

        /// Something for the user to DO: ask, or fix. `good` has nothing and
        /// `unknown` has nothing either - the app can't even tell them what.
        public var needsUser: Bool { self == .askable || self == .broken }
    }

    public var grade: Grade {
        switch self {
        case .good: .good
        case .askable: .askable
        case .broken: .broken
        case .unknown: .unknown
        }
    }

    /// Rendered only for the grades with a button (`askable`, `broken`).
    public var actionTitle: String {
        switch self {
        case .good, .unknown: ""
        case .askable(let title, _), .broken(let title, note: _): title
        }
    }

    public var note: String? {
        switch self {
        case .good: nil
        case .askable(_, let note): note
        case .broken(_, let note): note
        case .unknown(let note): note
        }
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
