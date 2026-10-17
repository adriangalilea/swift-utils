import Foundation
import Synchronization

/// The root logger. It writes the event stream of the logging contract shared
/// with go-utils, ts-utils and py-utils (github.com/adriangalilea/utils): what
/// Swift, Go, TypeScript and Python programs write is read, merged and traced
/// together, byte for byte.
///
/// Every verb takes a message, then fields. The message says what happened,
/// the fields say with what:
///
///     log.info("ready")
///     log.warn("retrying", ["attempt": 2])
///     log.error("charge failed", ["err": error])
///
/// Verbs say what happened and each prints at a fixed level: error and fail
/// (error), warn and warnOnce (warn), info, success, wait, ready and step
/// (info), debug, trace. Fields are an autoclosure: below the threshold they
/// are never built.
///
/// Scope is the subsystem: `log.scope("api").scope("auth")` writes scope
/// ["api","auth"] and filters by API_AUTH_LOG_LEVEL, then API_LOG_LEVEL, then
/// LOG_LEVEL, then setLogLevel, then info, read live on every event.
///
/// A span is a piece of work, and a span is a logger: what is written through
/// it belongs to it. It ends with its block, failed when the block throws:
///
///     try await log.span("charge", ["amount": amount]) { s in
///         s.warn("retrying", ["attempt": 2])
///         try await s.span("stripe") { c in … }
///         s.set(["receipt": receipt])
///     }
///
/// Work that does not fit a block opens and ends its span by hand, once:
/// `let s = log.begin("upload")` … `s.end()` or `s.end(error)`. There is no
/// ambient context: a function that logs inside a span takes the span.
///
/// A trace crosses processes explicitly: `s.traceparent` is the W3C value to
/// hand on (an HTTP header, a TRACEPARENT variable, a field of a message), and
/// `log.join(value)` returns a logger whose spans are its children. A process
/// started with TRACEPARENT set joins it for its root spans.
///
/// Output goes to stderr (stdout is data) and to Apple's unified log, each
/// by its own threshold: the stream (stderr, and what ships) by LOG_LEVEL
/// and the scope variables, for whoever reads this process; the unified log,
/// the record, by LOG_RECORD_LEVEL (`setLogRecordLevel`, default info), so a
/// command quiet at its terminal still records its spans and a trace that
/// crosses it has its part.
/// LOG_FORMAT=json writes one JSON event per line; human writes symbols,
/// colour, dim key=value fields and indented spans; the default is human at a
/// terminal, json elsewhere. LOG_TIME=1 opens human lines with the local
/// clock, LOG_SERVICE names the program, LOG_SHIP and LOG_SHIP_TOKEN ship the
/// JSON lines (Ship.swift), LOG_OSLOG=0 turns the unified log off. Each has a
/// setter, and the environment wins over it.
public let log = LogWriter()

/// What every logger does: the verbs, scopes, spans and joins. `LogWriter`
/// and `Span` are the two loggers.
public protocol Logging: Sendable {
    var writer: LogWriter { get }
}

/// A logger in a scope, inside a span when it is one's, under a remote span
/// when joined to one.
public struct LogWriter: Logging, Sendable {
    let scope: [String]
    /// The scope's LOG_LEVEL variables, most specific first.
    let levelVariables: [String]
    /// The span what is written here belongs to.
    let span: Span?
    /// The remote span root spans continue; nil: TRACEPARENT's, if any.
    let remote: Traceparent?

    public var writer: LogWriter { self }

    init(scope: [String] = [], levelVariables: [String] = [], span: Span? = nil, remote: Traceparent? = nil) {
        self.scope = scope
        self.levelVariables = levelVariables
        self.span = span
        self.remote = remote
    }

    /// Where an event at `level` goes from here (the stream, the record).
    func reach(_ level: LogLevel) -> Reach { Reach(level, levelVariables: levelVariables) }
    func enabled(_ level: LogLevel) -> Bool { !reach(level).isEmpty }

    func line(_ verb: Verb, _ message: String, _ fields: () -> Fields) {
        let reach = reach(verb.level)
        guard !reach.isEmpty else { return }
        write(verb, message, fields(), reach)
    }

    /// A line. Inside a span it carries the trace and the nearest shown span;
    /// with none shown it carries no ids, like a line outside any span.
    func write(_ verb: Verb, _ message: String, _ fields: Fields, _ reach: Reach) {
        var e = Event(time: Date(), verb: verb, msg: message, service: service(), scope: scope)
        if let span {
            precondition(!span.ended, "\"\(message)\" written to span \"\(span.name)\" after it ended")
            if let anchor = span.anchor {
                e.traceID = span.traceID
                e.spanID = anchor
            }
        }
        e.fields = encodeFields(fields)
        emit(e, reach)
    }
}

extension Logging {
    public func error(_ message: String, _ fields: @autoclosure () -> Fields = [:]) {
        writer.line(.error, message, fields)
    }
    public func fail(_ message: String, _ fields: @autoclosure () -> Fields = [:]) {
        writer.line(.fail, message, fields)
    }
    public func warn(_ message: String, _ fields: @autoclosure () -> Fields = [:]) {
        writer.line(.warn, message, fields)
    }
    public func info(_ message: String, _ fields: @autoclosure () -> Fields = [:]) {
        writer.line(.info, message, fields)
    }
    public func success(_ message: String, _ fields: @autoclosure () -> Fields = [:]) {
        writer.line(.success, message, fields)
    }
    public func wait(_ message: String, _ fields: @autoclosure () -> Fields = [:]) {
        writer.line(.wait, message, fields)
    }
    public func ready(_ message: String, _ fields: @autoclosure () -> Fields = [:]) {
        writer.line(.ready, message, fields)
    }
    public func step(_ message: String, _ fields: @autoclosure () -> Fields = [:]) {
        writer.line(.step, message, fields)
    }
    public func debug(_ message: String, _ fields: @autoclosure () -> Fields = [:]) {
        writer.line(.debug, message, fields)
    }
    public func trace(_ message: String, _ fields: @autoclosure () -> Fields = [:]) {
        writer.line(.trace, message, fields)
    }

    /// warn, once per message and scope for the life of the process. A
    /// warning filtered out does not count as seen.
    public func warnOnce(_ message: String, _ fields: @autoclosure () -> Fields = [:]) {
        let w = writer
        let reach = w.reach(.warn)
        guard !reach.isEmpty, firstTime(w.scope.joined(separator: "\u{0}") + "\u{1}" + message) else { return }
        w.write(.warn, message, fields(), reach)
    }

    /// A child whose events carry `name` after this logger's scope and whose
    /// level reads {SCOPE_PATH}_LOG_LEVEL first.
    public func scope(_ name: String) -> LogWriter {
        precondition(!name.isEmpty, "a scope needs a name")
        let w = writer
        let scope = w.scope + [name]
        return LogWriter(
            scope: scope, levelVariables: [levelVariable(scope)] + w.levelVariables, span: w.span,
            remote: w.remote)
    }

    /// A logger whose root spans are children of the remote span `traceparent`
    /// names. nil returns this logger. A malformed value is input from
    /// outside: it is ignored with a warning, once per distinct value.
    public func join(_ traceparent: String?) -> LogWriter {
        let w = writer
        guard let traceparent else { return w }
        do throws(Traceparent.Malformed) {
            return join(try Traceparent(parsing: traceparent))
        } catch {
            let reach = w.reach(.warn)
            if !reach.isEmpty, firstTime("\u{2}" + traceparent) {
                w.write(.warn, "malformed traceparent ignored", ["traceparent": traceparent, "why": error.reason], reach)
            }
            return w
        }
    }

    /// A logger whose root spans are children of `remote`.
    public func join(_ remote: Traceparent) -> LogWriter {
        let w = writer
        return LogWriter(scope: w.scope, levelVariables: w.levelVariables, remote: remote)
    }

    /// Opens a span and returns it; it stays open until `end` is called, once.
    /// Under a span it is that span's child, else a root span (of the joined
    /// remote span, else of TRACEPARENT's, else a new trace). Where it is
    /// shown is decided now, by its start's level against the stream's and
    /// the record's thresholds; its end follows that decision.
    public func begin(_ name: String, _ fields: Fields = [:]) -> Span {
        let w = writer
        let traceID: String
        let parentID: String?
        if let parent = w.span {
            precondition(!parent.ended, "span \"\(name)\" opened in \"\(parent.name)\" after it ended")
            traceID = parent.traceID
            parentID = parent.anchor
        } else if let remote = w.remote ?? environmentTraceparent {
            traceID = remote.traceID
            parentID = remote.spanID
        } else {
            traceID = newID(bytes: 16)
            parentID = nil
        }
        let s = Span(
            name: name, scope: w.scope, levelVariables: w.levelVariables, traceID: traceID,
            parentID: parentID, top: w.span == nil, reach: w.reach(Verb.wait.level), fields: fields)
        if s.shown {
            var e = s.own(.wait, .start)
            e.fields = encodeFields(fields)
            emit(e, s.reach)
        }
        return s
    }

    /// `begin` and `end` round a block: an error thrown out of it ends the span
    /// failed (fields.err) and is rethrown.
    public func span<T>(_ name: String, _ fields: Fields = [:], _ body: (Span) throws -> T) rethrows -> T {
        let s = begin(name, fields)
        do {
            let result = try body(s)
            s.end()
            return result
        } catch {
            s.end(error)
            throw error
        }
    }

    /// `begin` and `end` round an async block, run in the caller's isolation.
    public func span<T>(
        _ name: String, _ fields: Fields = [:], isolation: isolated (any Actor)? = #isolation,
        _ body: (Span) async throws -> T
    ) async rethrows -> T {
        let s = begin(name, fields)
        do {
            let result = try await body(s)
            s.end()
            return result
        } catch {
            s.end(error)
            throw error
        }
    }
}

/// TRACEPARENT is read once, at the first root span: it is how the process
/// was started, not something that changes.
private let environmentTraceparent: Traceparent? = {
    guard let value = env("TRACEPARENT") else { return nil }
    do throws(Traceparent.Malformed) {
        return try Traceparent(parsing: value)
    } catch {
        log.warn("malformed TRACEPARENT ignored", ["traceparent": value, "why": error.reason])
        return nil
    }
}()

/// A piece of work: a start event, the lines and spans written through it, an
/// end event. A span is a logger; `set` adds fields its end carries,
/// `traceparent` hands it to another process, `end` closes it once.
///
/// A hidden span (its start below the threshold) writes neither event, and
/// what it holds belongs to its nearest shown ancestor (`anchor`): its lines
/// carry that span's id, its children name it as parent, its traceparent
/// names it. A hidden span that fails still writes one fail line there.
public final class Span: Logging, Sendable {
    let name: String
    let traceID: String
    let spanID: String
    /// The shown span (or remote span) this one hangs from; nil for a root.
    let parentID: String?
    /// Where its start was written (the stream, the record), so its end
    /// will be there too.
    let reach: Reach
    /// Its start was written somewhere.
    var shown: Bool { !reach.isEmpty }
    /// What it holds belongs to: its own id when shown, else its parent's.
    let anchor: String?
    /// Opened outside any span of this process: its end ships what waits.
    let top: Bool
    let start: ContinuousClock.Instant
    let scope: [String]
    let levelVariables: [String]

    public var writer: LogWriter { LogWriter(scope: scope, levelVariables: levelVariables, span: self) }

    private struct State {
        var fields: Fields
        var ended = false
    }
    private let state: Mutex<State>

    init(
        name: String, scope: [String], levelVariables: [String], traceID: String, parentID: String?,
        top: Bool, reach: Reach, fields: Fields
    ) {
        precondition(!name.isEmpty, "a span needs a name")
        self.name = name
        self.traceID = traceID
        self.spanID = newID(bytes: 8)
        self.parentID = parentID
        self.reach = reach
        self.anchor = reach.isEmpty ? parentID : spanID
        self.top = top
        self.start = .now
        self.state = Mutex(State(fields: fields))
        self.scope = scope
        self.levelVariables = levelVariables
    }

    var ended: Bool { state.withLock { $0.ended } }

    /// Fields learned while the span runs, carried on its end event.
    public func set(_ fields: Fields) {
        state.withLock { s in
            precondition(!s.ended, "set on span \"\(name)\" after it ended")
            s.fields.merge(fields) { _, new in new }
        }
    }

    /// The W3C traceparent naming this span, for an HTTP header, a
    /// TRACEPARENT variable or a message crossing to another process. A
    /// hidden span names its nearest shown ancestor, its own id only when it
    /// has none.
    public var traceparent: Traceparent {
        Traceparent(traceID: traceID, spanID: anchor ?? spanID)
    }

    /// Closes the span: ok with no error, failed with `error` in fields.err.
    /// A span ends once; a second end is a programming error and traps.
    public func end(_ error: (any Error)? = nil) {
        let fields = state.withLock { s -> Fields in
            precondition(!s.ended, "span \"\(name)\" ended twice")
            s.ended = true
            return s.fields
        }
        let (seconds, attoseconds) = (ContinuousClock.now - start).components
        let durMs = ((Double(seconds) * 1e6 + Double(attoseconds) / 1e12).rounded()) / 1000
        defer { if top { send() } }
        var all = fields
        if let error { all["err"] = error }
        guard shown else {
            let failReach = writer.reach(.error)
            if error != nil, !failReach.isEmpty {
                all["dur_ms"] = durMs
                var e = Event(time: Date(), verb: .fail, msg: name, service: service(), scope: writer.scope)
                if let anchor {
                    e.traceID = traceID
                    e.spanID = anchor
                }
                e.fields = encodeFields(all)
                emit(e, failReach)
            }
            return
        }
        var e = own(error == nil ? .success : .fail, .end)
        e.durMs = durMs
        e.fields = encodeFields(all)
        emit(e, reach)
    }

    func own(_ verb: Verb, _ phase: Phase) -> Event {
        Event(
            time: Date(), verb: verb, msg: name, service: service(), scope: writer.scope, phase: phase,
            traceID: traceID, spanID: spanID, parentID: parentID)
    }
}
