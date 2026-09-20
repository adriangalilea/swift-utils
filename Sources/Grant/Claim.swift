import Foundation
import os

/// The claim/proof machine: THE authority on a capability whose system
/// readout can lie (an FSKit module the settings plist says is enabled
/// while fskitd serves nothing; any registry that mirrors intent, not
/// reality). One instance per capability; every surface renders from
/// `verdict` (through the owning Grant's standing), every real attempt is
/// REPORTED here, and any disagreement between prediction and reality is
/// a first-class journaled CONTRADICTION - the debugging surface this
/// machine exists for.
///
/// Epistemics, deliberately explicit:
/// - INTENT is the user's switch as the CONSUMER read it: on, off with the
///   reason the consumer knows (turned off; not even registered), or
///   unreadable - the system hides the switch - which is not off.
/// - PROOF is a real outcome: the only witness that cannot lie. A past
///   success is a witness of the PAST; only a capability seen live RIGHT
///   NOW speaks for the present when the switch can't be read.
/// - The verdict reconciles claim with evidence. It may be WRONG - and
///   when reality says so, the machine records the contradiction and
///   corrects itself. Never silently.
///
/// Knowledge sits where it lives: the consumer names why a switch is off
/// (it read the registry), the machine names only what IT learned - a
/// failure under a switch that claims on (`whenFailing`).
///
/// An unproven claim is NOT a problem: the owning Grant renders both
/// `.capable` and `.unproven` as `.good` (the switch is readable and on)
/// - proof is journal detail, never UI divergence. `.unknown` renders as
/// exactly that, never as good.
/// Isolation is the consumer's convention (main-thread by convention
/// matches an unannotated app model; annotating @MainActor here would
/// only manufacture isolation errors, not safety).
@Observable
public final class Claim<Reason: Equatable> {
    public enum Intent: Equatable, CustomStringConvertible {
        /// The switch reads on.
        case on
        /// The switch reads off, and the consumer knows why.
        case off(Reason)
        /// The system hides the switch from the app.
        case unreadable

        public var description: String {
            switch self {
            case .on: "on"
            case .off(let why): "off(\(why))"
            case .unreadable: "unreadable"
            }
        }
    }

    public enum Verdict: Equatable, CustomStringConvertible {
        /// The switch is on and a real success proved it - or the
        /// capability is live right now. Capable until reality says otherwise.
        case capable
        /// Intent says on; nothing has confirmed yet. Attempts proceed -
        /// the first success IS the confirmation.
        case unproven
        /// The switch can't be read and nothing is live to vouch for it.
        /// Attempts proceed; nothing is claimed either way.
        case unknown
        /// We believe an attempt cannot succeed now, and why. A belief:
        /// the user may try anyway, and a success is a recorded
        /// contradiction that flips the verdict.
        case impossible(Reason)

        public var description: String {
            switch self {
            case .capable: "capable"
            case .unproven: "unproven"
            case .unknown: "unknown"
            case .impossible(let why): "impossible(\(why))"
            }
        }
    }

    public enum Outcome: CustomStringConvertible {
        /// A real attempt succeeded.
        case succeeded
        /// The capability was seen ALREADY working (e.g. a live mount in
        /// the mount table) without this process attempting anything.
        case witnessed
        case failed(String)

        public var description: String {
            switch self {
            case .succeeded: "succeeded"
            case .witnessed: "witnessed"
            case .failed(let detail): "failed(\(detail))"
            }
        }
    }

    public private(set) var verdict: Verdict = .unproven
    /// The instrument: every transition and every contradiction, oldest
    /// first, capped. Render it verbatim in a debug surface.
    public private(set) var journal: [(at: Date, line: String)] = []

    private let whenFailing: Reason
    private let log: Logger
    private var proven = false
    private var lastFailure: String?

    /// `whenFailing` is the verdict's reason while the switch claims on
    /// (or can't be read) but the last attempt failed: the system is not
    /// serving what the switch claims.
    public init(whenFailing: Reason, log: Logger) {
        self.whenFailing = whenFailing
        self.log = log
    }

    /// Re-derive the verdict from intent plus everything reality has
    /// said. Call from the app's reconcile path (app-active + relevant
    /// system events - the liveness pattern) with the switch's current
    /// read and whether the capability is live right now.
    public func evaluate(intent: Intent, live: Bool) {
        if live, !proven { observe(.witnessed) }
        let next: Verdict =
            switch intent {
            case .off(let why): .impossible(why)
            case .on:
                proven ? .capable : lastFailure != nil ? .impossible(whenFailing) : .unproven
            case .unreadable:
                // A past success does not speak for a switch nobody can
                // read; only the capability live NOW does.
                live ? .capable : lastFailure != nil ? .impossible(whenFailing) : .unknown
            }
        transition(to: next, cause: "evaluate(\(intent))")
    }

    /// Reality reports. A contradiction is reality disagreeing with the
    /// standing verdict - exactly what this machine exists to record.
    public func observe(_ outcome: Outcome) {
        switch outcome {
        case .succeeded, .witnessed:
            if case .impossible(let why) = verdict {
                contradiction("\(outcome) while predicted impossible(\(why))")
            }
            proven = true
            lastFailure = nil
            transition(to: .capable, cause: "observe(\(outcome))")
        case .failed(let detail):
            if verdict == .capable {
                contradiction("failed while predicted capable: \(detail)")
            }
            proven = false
            lastFailure = detail
            // Intent is re-read on the next evaluate(); until then the
            // honest floor for a failure under an on-switch:
            transition(to: .impossible(whenFailing), cause: "observe(failed)")
        }
    }

    private func transition(to next: Verdict, cause: String) {
        guard next != verdict else { return }
        record("\(verdict) → \(next)  [\(cause)]")
        verdict = next
    }

    private func contradiction(_ line: String) {
        record("CONTRADICTION: \(line)")
    }

    private func record(_ line: String) {
        journal.append((Date(), line))
        if journal.count > 64 { journal.removeFirst() }
        log.notice("\(line, privacy: .public)")
    }
}
