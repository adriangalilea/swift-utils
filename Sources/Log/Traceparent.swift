/// A W3C Trace Context `traceparent` value: `00-<trace_id>-<parent_id>-<flags>`,
/// the span a trace continues from in another process. It travels as an HTTP
/// `traceparent` header, the `TRACEPARENT` variable of a spawned process, or a
/// field of any message that crosses a boundary.
///
/// Parsing is the W3C rule, exactly: lowercase hex; a 16-byte trace id and an
/// 8-byte parent id, neither all zeros; version `ff` invalid; version `00`
/// exactly 55 characters; a later version may append fields after a dash.
/// What it writes is always version 00.
public struct Traceparent: Sendable, Hashable, CustomStringConvertible, Codable {
    /// 32 lowercase hex.
    public let traceID: String
    /// 16 lowercase hex: the span the trace continues from.
    public let spanID: String
    /// Bit 0 is `sampled`.
    public let flags: UInt8

    public var description: String {
        "00-\(traceID)-\(spanID)-\(flags < 16 ? "0" : "")\(String(flags, radix: 16))"
    }

    /// Why a value is not a traceparent, with the value itself.
    public struct Malformed: Error, CustomStringConvertible, Sendable {
        public let value: String
        public let reason: String
        public var description: String { "malformed traceparent \"\(value)\": \(reason)" }
    }

    public init(parsing v: String) throws(Malformed) {
        func reject(_ reason: String) -> Malformed { Malformed(value: v, reason: reason) }
        let b = Array(v.utf8)
        guard b.count >= 55 else { throw reject("shorter than 55 characters") }
        guard b[2] == UInt8(ascii: "-"), b[35] == UInt8(ascii: "-"), b[52] == UInt8(ascii: "-") else {
            throw reject("dashes not at 2, 35 and 52")
        }
        let version = b[0..<2], trace = b[3..<35], span = b[36..<52], flags = b[53..<55]
        guard [version, trace, span, flags].allSatisfy(lowerHex) else { throw reject("not lowercase hex") }
        guard !version.elementsEqual("ff".utf8) else { throw reject("version ff") }
        if version.elementsEqual("00".utf8) {
            guard b.count == 55 else { throw reject("version 00 with trailing data") }
        } else if b.count > 55, b[55] != UInt8(ascii: "-") {
            throw reject("a later version's extra fields must follow a dash")
        }
        guard trace.contains(where: { $0 != UInt8(ascii: "0") }) else { throw reject("all-zero trace id") }
        guard span.contains(where: { $0 != UInt8(ascii: "0") }) else { throw reject("all-zero parent id") }
        traceID = String(decoding: trace, as: UTF8.self)
        spanID = String(decoding: span, as: UTF8.self)
        self.flags = UInt8(String(decoding: flags, as: UTF8.self), radix: 16)!
    }

    init(traceID: String, spanID: String) {
        assert(traceID.utf8.count == 32 && lowerHex(traceID.utf8[...]), "trace id \(traceID)")
        assert(spanID.utf8.count == 16 && lowerHex(spanID.utf8[...]), "span id \(spanID)")
        self.traceID = traceID
        self.spanID = spanID
        self.flags = 1
    }

    /// Decoding is parsing: a stored or received value that is not a
    /// traceparent fails to decode, it is never carried along broken.
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        do {
            self = try Traceparent(parsing: value)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.description))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

private func lowerHex<C: Collection<UInt8>>(_ s: C) -> Bool {
    s.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
}

/// n random bytes as lowercase hex, never all zeros (W3C forbids it).
func newID(bytes n: Int) -> String {
    var g = SystemRandomNumberGenerator()
    while true {
        let b = (0..<n).map { _ in UInt8.random(in: .min ... .max, using: &g) }
        if b.contains(where: { $0 != 0 }) {
            return b.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
        }
    }
}
