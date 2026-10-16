import Foundation

/// A threshold an event's level is compared against: an event shows when its
/// level is at or below it. `silent` is a threshold only, never an event's.
public enum LogLevel: Int, Sendable, Comparable, CaseIterable {
    case silent, error, warn, info, debug, trace

    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }

    var name: String {
        switch self {
        case .silent: "silent"
        case .error: "error"
        case .warn: "warn"
        case .info: "info"
        case .debug: "debug"
        case .trace: "trace"
        }
    }

    /// The contract's spellings, matched without regard to case.
    init?(parsing value: String) {
        let lower = value.lowercased()
        guard let level = LogLevel.allCases.first(where: { $0.name == lower }) else { return nil }
        self = level
    }
}

/// What happened. Each verb prints at a fixed level with a fixed symbol.
enum Verb: Sendable {
    case error, fail, warn, info, success, wait, ready, step, debug, trace

    var name: String {
        switch self {
        case .error: "error"
        case .fail: "fail"
        case .warn: "warn"
        case .info: "info"
        case .success: "success"
        case .wait: "wait"
        case .ready: "ready"
        case .step: "step"
        case .debug: "debug"
        case .trace: "trace"
        }
    }

    var level: LogLevel {
        switch self {
        case .error, .fail: .error
        case .warn: .warn
        case .info, .success, .wait, .ready, .step: .info
        case .debug: .debug
        case .trace: .trace
        }
    }

    /// The human rendering's symbol; info's is a space so lines stay aligned.
    var symbol: String {
        switch self {
        case .error, .fail: "⨯"
        case .warn: "⚠"
        case .info: " "
        case .success: "✓"
        case .wait: "○"
        case .ready: "▶"
        case .step: "•"
        case .debug: "◦"
        case .trace: "»"
        }
    }

    /// The symbol's ANSI colour (bold is added), xterm's base eight.
    var color: String {
        switch self {
        case .error, .fail: "\u{1B}[31m"
        case .warn: "\u{1B}[33m"
        case .info, .wait: "\u{1B}[37m"
        case .success, .ready: "\u{1B}[32m"
        case .step, .debug: "\u{1B}[90m"
        case .trace: "\u{1B}[35m"
        }
    }
}

enum Phase: Sendable { case start, end }

/// One field: its key, its value as JSON text, and how it reads after `key=`
/// in the human rendering (a string as its text, an error as its message).
struct Field: Sendable {
    let key: String
    let json: String
    let human: String
}

/// One event of the stream. Status follows the verb on an end (success: ok,
/// fail: error); `durMs` is set exactly on an end.
struct Event: Sendable {
    var time: Date
    var verb: Verb
    var msg: String
    var service: String
    var scope: [String]
    var phase: Phase? = nil
    var traceID: String? = nil
    var spanID: String? = nil
    var parentID: String? = nil
    var durMs: Double? = nil
    var fields: [Field] = []

    /// The JSON line, no newline: keys in the contract's order, each only
    /// with a value.
    var json: String {
        var b = "{\"time\":"
        b.reserveCapacity(160)
        appendString(&b, instant(time))
        b += ",\"level\":"
        appendString(&b, verb.level.name)
        b += ",\"verb\":"
        appendString(&b, verb.name)
        b += ",\"msg\":"
        appendString(&b, msg)
        b += ",\"service\":"
        appendString(&b, service)
        if !scope.isEmpty {
            b += ",\"scope\":["
            for (i, s) in scope.enumerated() {
                if i > 0 { b += "," }
                appendString(&b, s)
            }
            b += "]"
        }
        switch phase {
        case .start: b += ",\"phase\":\"start\""
        case .end: b += ",\"phase\":\"end\""
        case nil: break
        }
        if let traceID { b += ",\"trace_id\":\"\(traceID)\"" }
        if let spanID { b += ",\"span_id\":\"\(spanID)\"" }
        if let parentID { b += ",\"parent_id\":\"\(parentID)\"" }
        if phase == .end, let durMs {
            b += verb == .fail ? ",\"status\":\"error\"" : ",\"status\":\"ok\""
            b += ",\"dur_ms\":"
            b += jsNumber(durMs)
        }
        if !fields.isEmpty {
            b += ",\"fields\":{"
            for (i, f) in fields.enumerated() {
                if i > 0 { b += "," }
                appendString(&b, f.key)
                b += ":"
                b += f.json
            }
            b += "}"
        }
        b += "}"
        return b
    }
}

/// The event instant: UTC, RFC3339 with milliseconds.
func instant(_ date: Date) -> String {
    let ms = (date.timeIntervalSince1970 * 1000).rounded(.down)
    var seconds = time_t(ms / 1000)
    var parts = tm()
    gmtime_r(&seconds, &parts)
    let millis = Int(ms - Double(seconds) * 1000)
    return String(
        format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", parts.tm_year + 1900, parts.tm_mon + 1,
        parts.tm_mday, parts.tm_hour, parts.tm_min, parts.tm_sec, millis)
}

/// The local wall clock a human line opens with under LOG_TIME=1.
func clock(_ date: Date) -> String {
    var seconds = time_t(date.timeIntervalSince1970)
    var parts = tm()
    localtime_r(&seconds, &parts)
    return String(format: "%02d:%02d:%02d", parts.tm_hour, parts.tm_min, parts.tm_sec)
}

/// A JSON string the way JavaScript's JSON.stringify writes one, so every
/// language writes the same bytes: only the quote, the backslash and control
/// characters are escaped.
func appendString(_ b: inout String, _ s: String) {
    b += "\""
    var run = s.unicodeScalars.startIndex
    let scalars = s.unicodeScalars
    for i in scalars.indices {
        let c = scalars[i]
        let escape: String
        switch c {
        case "\"": escape = "\\\""
        case "\\": escape = "\\\\"
        case "\n": escape = "\\n"
        case "\r": escape = "\\r"
        case "\t": escape = "\\t"
        case "\u{08}": escape = "\\b"
        case "\u{0C}": escape = "\\f"
        default:
            guard c.value < 0x20 else { continue }
            escape = String(format: "\\u%04x", c.value)
        }
        b.unicodeScalars.append(contentsOf: scalars[run..<i])
        b += escape
        run = scalars.index(after: i)
    }
    b.unicodeScalars.append(contentsOf: scalars[run...])
    b += "\""
}

/// A number the way JavaScript prints one (ECMAScript Number-to-String, which
/// Go's encoding/json also follows): shortest round-trip digits, positional
/// from 1e-7 up to 1e21, exponent outside it, -0 as 0. NaN and the
/// infinities are not JSON numbers; the contract writes them as strings.
func jsNumber(_ x: Double) -> String {
    if x.isNaN { return "\"NaN\"" }
    if x.isInfinite { return x > 0 ? "\"Infinity\"" : "\"-Infinity\"" }
    if x == 0 { return "0" }
    // Swift's description is the shortest round-trip form ("1.5", "1e-07",
    // "1.2345678901234568e+20"); read its digits and decimal exponent.
    let text = x.magnitude.description
    let parts = text.split(separator: "e", maxSplits: 1)
    let exponent = parts.count == 2 ? Int(parts[1])! : 0
    let mantissa = parts[0].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    var digits = Array(mantissa[0].utf8) + (mantissa.count == 2 ? Array(mantissa[1].utf8) : [])
    // The value is 0.<digits> × 10^n.
    var n = mantissa[0].utf8.count + exponent
    while digits.first == UInt8(ascii: "0") {
        digits.removeFirst()
        n -= 1
    }
    while digits.last == UInt8(ascii: "0") { digits.removeLast() }
    assert(!digits.isEmpty, "a non-zero double \(x) printed no digits: \(text)")
    let d = String(decoding: digits, as: UTF8.self)
    let k = digits.count
    var out: String
    if k <= n && n <= 21 {
        out = d + String(repeating: "0", count: n - k)
    } else if 0 < n && n <= 21 {
        out = String(d.prefix(n)) + "." + String(d.dropFirst(n))
    } else if -6 < n && n <= 0 {
        out = "0." + String(repeating: "0", count: -n) + d
    } else {
        let e = n - 1
        let m = k == 1 ? d : String(d.prefix(1)) + "." + String(d.dropFirst())
        out = m + "e" + (e > 0 ? "+" : "-") + String(abs(e))
    }
    return x < 0 ? "-" + out : out
}
