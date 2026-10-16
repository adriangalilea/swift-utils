import Foundation
import Synchronization
import os

// The program's own defaults, set by the setters. For every one of them the
// environment, read live on each event, wins: the operator's variable
// overrides what code chose. Values match in any case, an empty variable is
// unset, and an unknown value is a configuration error that stops the
// program: a confused program screams.

struct Settings: Sendable {
    var level: LogLevel = .info
    var format: Format? = nil
    var time = false
    var service: String? = nil
    var ship: String? = nil
    var shipToken: String? = nil
    var osLog = true
}

enum Format: String, Sendable { case human, json }

let settings = locked(Settings())

/// Every global Mutex is built through this. Swift 6.4 at -O folds a global
/// `Mutex(value)` into static data and leaves it zeroed (the level read as
/// silent, stderr as fd 0); an initializer it cannot see through is run.
@inline(never)
func locked<Value: ~Copyable>(_ value: consuming sending Value) -> Mutex<Value> {
    Mutex(value)
}

/// The program's default threshold; LOG_LEVEL and {SCOPE}_LOG_LEVEL override it.
public func setLogLevel(_ level: String) {
    let parsed = parseLevel("setLogLevel", level)
    settings.withLock { $0.level = parsed }
}

/// The program's default rendering, "human" or "json"; LOG_FORMAT overrides it.
public func setLogFormat(_ format: String) {
    let parsed = parseFormat("setLogFormat", format)
    settings.withLock { $0.format = parsed }
}

/// Whether human lines open with the local HH:MM:SS; LOG_TIME overrides it.
public func setLogTime(_ on: Bool) {
    settings.withLock { $0.time = on }
}

/// The program's name in every event; LOG_SERVICE overrides it.
public func setLogService(_ name: String) {
    precondition(!name.isEmpty, "setLogService: a service needs a name")
    settings.withLock { $0.service = name }
}

/// Whether each event is also written to Apple's unified log (default on);
/// LOG_OSLOG=1|0 overrides it. The subsystem is the bundle identifier (else
/// the service), the category the scope path joined by dots ("root"
/// unscoped), the message the event's JSON line, at the matching OSLogType.
public func setLogOSLog(_ on: Bool) {
    settings.withLock { $0.osLog = on }
}

func env(_ name: String) -> String? {
    guard let raw = getenv(name) else { return nil }
    let value = String(cString: raw)
    return value.isEmpty ? nil : value
}

func parseLevel(_ source: String, _ value: String) -> LogLevel {
    guard let level = LogLevel(parsing: value) else {
        fatalError("\(source): unknown log level \"\(value)\" (want silent, error, warn, info, debug, trace)")
    }
    return level
}

func parseFormat(_ source: String, _ value: String) -> Format {
    guard let format = Format(rawValue: value.lowercased()) else {
        fatalError("\(source): unknown format \"\(value)\" (want human, json)")
    }
    return format
}

/// ["api", "auth-v2"] -> "API_AUTH_V2_LOG_LEVEL".
func levelVariable(_ scope: [String]) -> String {
    let segments = scope.map { segment in
        String(
            String.UnicodeScalarView(
                segment.uppercased().unicodeScalars.map {
                    ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) ? $0 : "_"
                }))
    }
    return segments.joined(separator: "_") + "_LOG_LEVEL"
}

/// The threshold for a scope whose variables, most specific first, are
/// `variables`: the first set, then LOG_LEVEL, then setLogLevel, then info.
func threshold(_ variables: [String]) -> LogLevel {
    for name in variables {
        if let value = env(name) { return parseLevel(name, value) }
    }
    if let value = env("LOG_LEVEL") { return parseLevel("LOG_LEVEL", value) }
    return settings.withLock { $0.level }
}

private let stderrTTY = isatty(STDERR_FILENO) == 1

func format() -> Format {
    if let value = env("LOG_FORMAT") { return parseFormat("LOG_FORMAT", value) }
    return settings.withLock { $0.format } ?? (stderrTTY ? .human : .json)
}

func timeOn() -> Bool {
    if let value = env("LOG_TIME") {
        precondition(value == "1" || value == "0", "LOG_TIME: unknown value \"\(value)\" (want 1, 0)")
        return value == "1"
    }
    return settings.withLock { $0.time }
}

func osLogOn() -> Bool {
    if let value = env("LOG_OSLOG") {
        precondition(value == "1" || value == "0", "LOG_OSLOG: unknown value \"\(value)\" (want 1, 0)")
        return value == "1"
    }
    return settings.withLock { $0.osLog }
}

func service() -> String {
    if let name = env("LOG_SERVICE") { return name }
    if let name = settings.withLock({ $0.service }) { return name }
    let name = (ProcessInfo.processInfo.processName as NSString).deletingPathExtension
    precondition(!name.isEmpty, "no executable name to call the service, set LOG_SERVICE")
    return name
}

private func color(_ fd: Int32) -> Bool {
    if env("NO_COLOR") != nil { return false }
    if env("FORCE_COLOR") != nil { return true }
    return fd == STDERR_FILENO ? stderrTTY : isatty(fd) == 1
}

// MARK: - Writing

/// What the human rendering keeps across events: each open span's depth, so
/// a span's contents indent under it. Derived from the stream's own ids, as
/// the `logs` viewer derives it, so writer and viewer agree.
private struct Human {
    var depth: [String: Int] = [:]

    mutating func place(_ e: Event) -> Int {
        func under(_ id: String?) -> Int { id.flatMap { depth[$0] }.map { $0 + 1 } ?? 0 }
        switch e.phase {
        case .start:
            let d = under(e.parentID)
            depth[e.spanID!] = d
            return d
        case .end:
            let d = depth.removeValue(forKey: e.spanID!) ?? under(e.parentID)
            return d
        case nil:
            return under(e.spanID)
        }
    }

    mutating func render(_ e: Event, clock showClock: Bool, color on: Bool) -> String {
        let reset = "\u{1B}[0m"
        func dim(_ s: String) -> String { on ? "\u{1B}[2m" + s + reset : s }
        var b = showClock ? dim(clock(e.time)) + " " : ""
        b += String(repeating: "  ", count: place(e))
        if e.verb == .step { b += "  " }
        b += on ? e.verb.color + "\u{1B}[1m" + e.verb.symbol + reset : e.verb.symbol
        b += " "
        if !e.scope.isEmpty { b += dim("[" + e.scope.joined(separator: " ") + "]") + " " }
        b += e.msg
        if e.phase == .end, let ms = e.durMs { b += " " + dim(humanDuration(ms)) }
        for f in e.fields { b += " " + dim(f.key + "=" + f.human) }
        return b + "\n"
    }
}

/// 0.012ms, 3.4ms, 254ms, 1.25s, then whole minutes and seconds.
func humanDuration(_ ms: Double) -> String {
    switch ms {
    case ..<1: String(format: "%.3fms", ms)
    case ..<10: String(format: "%.1fms", ms)
    case ..<1000: String(format: "%.0fms", ms)
    case ..<60_000: String(format: "%.2fs", ms / 1000)
    default: "\(Int(ms / 60_000))m\(Int((ms.truncatingRemainder(dividingBy: 60_000) / 1000).rounded()))s"
    }
}

/// One write at a time: a line is never interleaved with another, the human
/// depth stays coherent, and a ship batch holds lines in stderr's order.
private struct Output {
    var human = Human()
    /// stderr; the tests read the stream through a pipe here.
    var fd = STDERR_FILENO
}

private let output = locked(Output())

/// Points the stream at `fd` (a test's pipe) and forgets the human depths.
func redirect(_ fd: Int32) {
    output.withLock { $0 = Output(fd: fd) }
}

private let osLoggers = locked([String: os.Logger]())

private func osLogger(_ scope: [String]) -> os.Logger {
    let category = scope.isEmpty ? "root" : scope.joined(separator: ".")
    return osLoggers.withLock { loggers in
        if let l = loggers[category] { return l }
        let l = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? service(), category: category)
        loggers[category] = l
        return l
    }
}

private func osLogType(_ level: LogLevel) -> OSLogType {
    switch level {
    case .error: .error
    // info is persisted like warn: a daemon's journey is what it wrote at info.
    case .warn, .info: .default
    case .debug, .trace, .silent: .debug
    }
}

/// Writes the event to stderr in the format chosen, to the unified log, and
/// to the ship batch when LOG_SHIP is set. Every knob resolves on every
/// event, so a bad variable screams under any rendering.
func emit(_ e: Event) {
    let fmt = format()
    let showClock = timeOn()
    let target = shipTarget()
    let useOSLog = osLogOn()
    let json = fmt == .json || target != nil || useOSLog ? e.json : ""
    let tooLarge: Int? = output.withLock { out in
        let text = fmt == .json ? json + "\n" : out.human.render(e, clock: showClock, color: color(out.fd))
        writeAll(out.fd, text)
        if useOSLog {
            osLogger(e.scope).log(level: osLogType(e.verb.level), "\(json, privacy: .public)")
        }
        guard let target else { return nil }
        return ship(target, json) ? nil : json.utf8.count
    }
    if let tooLarge {
        shipLog.warnOnce("event too large to ship", ["bytes": tooLarge, "limit": shipMaxBytes])
    }
}

/// A failed write to stderr is dropped: there is nowhere left to report it.
private func writeAll(_ fd: Int32, _ text: String) {
    var text = text
    text.withUTF8 { buffer in
        var offset = 0
        while offset < buffer.count {
            let n = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
            if n < 0 {
                if errno == EINTR { continue }
                return
            }
            offset += n
        }
    }
}

// MARK: - warnOnce

/// Keys already warned about, bounded: past 1024 it forgets them all, and an
/// old warning printing once more is the honest failure for a daemon.
private let warned = locked(Set<String>())

func firstTime(_ key: String) -> Bool {
    warned.withLock { set in
        if set.contains(key) { return false }
        if set.count >= 1024 { set.removeAll() }
        set.insert(key)
        return true
    }
}
