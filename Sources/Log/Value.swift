import Foundation

/// The fields of an event: what happened with. Keys are written sorted at
/// every depth; values become JSON by the contract's one table, so a value
/// reads the same from every language:
///
/// - String, Bool, integers, floating point, nil: themselves (NaN and the
///   infinities as the strings "NaN", "Infinity", "-Infinity"; integers past
///   ±(2^53-1), which a JavaScript reader would round, as strings)
/// - an Error: `{"type", "message", "cause"?}`: its type name, its message
///   (LocalizedError's description, else its own description), and an
///   NSError's underlying error as the cause
/// - Date: the event-time string; Duration: milliseconds; Data: base64;
///   Decimal: a string
/// - arrays, sets, dictionaries: JSON, recursively (a non-string key by its
///   description, a set sorted by its elements' JSON)
/// - anything Encodable: its own JSON form
/// - anything else: its description
public typealias Fields = [String: any Sendable]

func encodeFields(_ fields: Fields) -> [Field] {
    sortedPairs(fields).map { key, value in
        var json = ""
        encode(value, into: &json)
        let human: String
        if let s = unwrap(value) as? String {
            human = humanText(s)
        } else if let e = unwrap(value) as? any Error {
            human = humanText(errorMessage(e))
        } else {
            human = json
        }
        return Field(key: key, json: json, human: human)
    }
}

/// Lexicographic by UTF-8 bytes, which is code point order: the order Go,
/// Python and JavaScript sort the same keys in.
func sortedPairs<V>(_ d: [String: V]) -> [(String, V)] {
    d.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }.map { ($0.key, $0.value) }
}

private protocol AnyOptional {
    var wrapped: Any? { get }
}

extension Optional: AnyOptional {
    var wrapped: Any? { map { $0 as Any } }
}

/// The value inside any depth of Optional; nil when there is none.
private func unwrap(_ v: Any) -> Any? {
    if let o = v as? AnyOptional {
        guard let inner = o.wrapped else { return nil }
        return unwrap(inner)
    }
    return v
}

/// Integers JavaScript holds exactly; past them a reader would round.
/// UInt64: a watch's Int is 32 bits.
private let maxSafeInteger: UInt64 = 9_007_199_254_740_991

private func isSafe<I: BinaryInteger>(_ i: I) -> Bool { i.magnitude <= maxSafeInteger }

func encode(_ value: Any, into b: inout String) {
    guard let v = unwrap(value) else {
        b += "null"
        return
    }
    // Foundation's numbers first: a dynamic cast would read 1 as true.
    if let n = v as? NSNumber, type(of: v) is NSNumber.Type {
        encodeNumber(n, into: &b)
        return
    }
    switch v {
    case let s as String:
        appendString(&b, s)
    case let x as Bool:
        b += x ? "true" : "false"
    case let i as any BinaryInteger:
        if isSafe(i) {
            b += String(describing: i)
        } else {
            appendString(&b, String(describing: i))
        }
    case let f as Float:
        // Float's shortest digits, not those of its widened Double.
        b += jsNumber(Double(f.description)!)
    case let f as any BinaryFloatingPoint:
        b += jsNumber(Double(f))
    case let d as Date:
        appendString(&b, instant(d))
    case let d as Duration:
        let (seconds, attoseconds) = d.components
        b += jsNumber(Double(seconds) * 1000 + Double(attoseconds) / 1e15)
    case let d as Data:
        appendString(&b, d.base64EncodedString())
    case let d as Decimal:
        appendString(&b, d.description)
    case let e as any Error:
        encodeError(e, into: &b)
    case let d as [String: Any]:
        encodeObject(sortedPairs(d), into: &b)
    case let d as [AnyHashable: Any]:
        encodeObject(
            sortedPairs(
                Dictionary(d.map { (String(describing: $0.key.base), $0.value) }) { a, _ in a }),
            into: &b)
    case let a as [Any]:
        b += "["
        for (i, x) in a.enumerated() {
            if i > 0 { b += "," }
            encode(x, into: &b)
        }
        b += "]"
    default:
        let mirror = Mirror(reflecting: v)
        if mirror.displayStyle == .set {
            let items = mirror.children.map { child -> String in
                var s = ""
                encode(child.value, into: &s)
                return s
            }
            b +=
                "["
                + items.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.joined(separator: ",")
                + "]"
        } else if let e = v as? any Encodable, let json = encodable(e) {
            b += json
        } else {
            appendString(&b, String(describing: v))
        }
    }
}

private func encodeObject(_ pairs: [(String, Any)], into b: inout String) {
    b += "{"
    for (i, (k, x)) in pairs.enumerated() {
        if i > 0 { b += "," }
        appendString(&b, k)
        b += ":"
        encode(x, into: &b)
    }
    b += "}"
}

private func encodeNumber(_ n: NSNumber, into b: inout String) {
    if CFGetTypeID(n) == CFBooleanGetTypeID() {
        b += n.boolValue ? "true" : "false"
        return
    }
    switch UInt8(n.objCType.pointee) {
    case UInt8(ascii: "f"), UInt8(ascii: "d"):
        b += jsNumber(n.doubleValue)
    case UInt8(ascii: "Q"):
        encode(n.uint64Value, into: &b)
    default:
        encode(n.int64Value, into: &b)
    }
}

/// An error's message as it was given: LocalizedError's description, an
/// NSError's localized description, else what the type says of itself.
func errorMessage(_ e: any Error) -> String {
    if let localized = e as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    if type(of: e) is NSError.Type {
        return (e as NSError).localizedDescription
    }
    return String(describing: e)
}

private func encodeError(_ e: any Error, into b: inout String) {
    b += "{\"type\":"
    appendString(&b, String(describing: type(of: e)))
    b += ",\"message\":"
    appendString(&b, errorMessage(e))
    if type(of: e) is NSError.Type,
        let cause = (e as NSError).userInfo[NSUnderlyingErrorKey] as? any Error
    {
        b += ",\"cause\":"
        encodeError(cause, into: &b)
    }
    b += "}"
}

/// An Encodable value's own JSON form, re-encoded by the contract's rules
/// (sorted keys, JavaScript numbers). nil when it does not encode.
private func encodable(_ value: any Encodable) -> String? {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
        var c = encoder.singleValueContainer()
        try c.encode(instant(date))
    }
    guard let data = try? encoder.encode(value),
        let tree = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    else { return nil }
    var b = ""
    encodeFoundation(tree, into: &b)
    return b
}

private func encodeFoundation(_ v: Any, into b: inout String) {
    switch v {
    case is NSNull: b += "null"
    case let n as NSNumber: encodeNumber(n, into: &b)
    case let s as String: appendString(&b, s)
    case let a as [Any]:
        b += "["
        for (i, x) in a.enumerated() {
            if i > 0 { b += "," }
            encodeFoundation(x, into: &b)
        }
        b += "]"
    case let d as [String: Any]:
        b += "{"
        for (i, (k, x)) in sortedPairs(d).enumerated() {
            if i > 0 { b += "," }
            appendString(&b, k)
            b += ":"
            encodeFoundation(x, into: &b)
        }
        b += "}"
    default:
        preconditionFailure("JSONSerialization produced \(type(of: v))")
    }
}

/// How a string reads after `key=` in a human line: as itself, quoted when
/// it is empty or holds a space, a quote, an `=` or anything unprintable.
func humanText(_ s: String) -> String {
    let plain =
        !s.isEmpty
        && !s.unicodeScalars.contains {
            $0 == " " || $0 == "\"" || $0 == "=" || $0.properties.generalCategory == .control
                || $0.properties.isWhitespace
        }
    if plain { return s }
    var b = ""
    appendString(&b, s)
    return b
}
