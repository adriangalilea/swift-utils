import Foundation
import Testing

@testable import Log

// W3C traceparent: what is written parses back to itself; what breaks the
// rule is refused with the reason, never repaired.
@Test func traceparentRoundTrip() throws {
    let value = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
    let t = try Traceparent(parsing: value)
    #expect(t.traceID == "0af7651916cd43dd8448eb211c80319c")
    #expect(t.spanID == "b7ad6b7169203331")
    #expect(t.flags == 1)
    #expect(t.description == value)
    let decoded = try JSONDecoder().decode(Traceparent.self, from: JSONEncoder().encode(t))
    #expect(decoded == t)
    // A later version may carry more after a dash; it is written back as 00.
    #expect(try Traceparent(parsing: "01-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-00-x").flags == 0)
}

@Test(arguments: [
    "",
    "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-0",  // short
    "00-0AF7651916CD43DD8448EB211C80319C-b7ad6b7169203331-01",  // upper case
    "ff-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01",  // version ff
    "00-00000000000000000000000000000000-b7ad6b7169203331-01",  // zero trace
    "00-0af7651916cd43dd8448eb211c80319c-0000000000000000-01",  // zero span
    "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01-x",  // 00 with more
    "01-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01x",  // no dash
    "00_0af7651916cd43dd8448eb211c80319c_b7ad6b7169203331_01",
])
func traceparentRejects(_ value: String) {
    #expect(throws: Traceparent.Malformed.self) { try Traceparent(parsing: value) }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Traceparent.self, from: JSONEncoder().encode(value))
    }
}

@Test func idsAreLowercaseHex() {
    for _ in 0..<100 {
        let id = newID(bytes: 8)
        #expect(id.count == 16)
        #expect(id.allSatisfy { "0123456789abcdef".contains($0) })
    }
}

// Numbers as JavaScript prints them.
@Test func numbers() {
    #expect(jsNumber(2.0) == "2")
    #expect(jsNumber(1.5) == "1.5")
    #expect(jsNumber(-0.0) == "0")
    #expect(jsNumber(1e-7) == "1e-7")
    #expect(jsNumber(0.000001) == "0.000001")
    #expect(jsNumber(1e21) == "1e+21")
    #expect(jsNumber(1e20) == "100000000000000000000")
    #expect(jsNumber(123.456) == "123.456")
    #expect(jsNumber(-1234.5e-10) == "-1.2345e-7")
    #expect(jsNumber(.nan) == "\"NaN\"")
    #expect(jsNumber(-.infinity) == "\"-Infinity\"")
    #expect(jsNumber(5e-324) == "5e-324")
}

struct Broken: Error, CustomStringConvertible { let description: String }
struct Receipt: Encodable { let id: String; let cents: Int; let at: Date }

// Field values by the contract's table, keys sorted at every depth.
@Test func fieldValues() {
    func json(_ f: Fields) -> String {
        "{" + encodeFields(f).map { "\"\($0.key)\":\($0.json)" }.joined(separator: ",") + "}"
    }
    #expect(json(["took": 1.5, "nested": ["b": [true, nil] as [Bool?], "a": 1] as Fields]) ==
        #"{"nested":{"a":1,"b":[true,null]},"took":1.5}"#)
    #expect(json(["err": Broken(description: "boom")]) == #"{"err":{"type":"Broken","message":"boom"}}"#)
    #expect(json(["n": 9_007_199_254_740_993, "m": -3]) == #"{"m":-3,"n":"9007199254740993"}"#)
    #expect(json(["s": "a\"b\n\u{1}é"]) == #"{"s":"a\"b\n\u0001é"}"#)
    #expect(json(["t": Date(timeIntervalSince1970: 1_760_271_639.1239)]) == #"{"t":"2025-10-12T12:20:39.123Z"}"#)
    #expect(json(["d": Duration.milliseconds(1500), "b": Data([1, 2, 3])]) == #"{"b":"AQID","d":1500}"#)
    #expect(json(["set": Set([3, 1, 2]), "map": [2: "x"]]) == #"{"map":{"2":"x"},"set":[1,2,3]}"#)
    #expect(json(["r": Receipt(id: "r1", cents: 250, at: Date(timeIntervalSince1970: 0))]) ==
        #"{"r":{"at":"1970-01-01T00:00:00.000Z","cents":250,"id":"r1"}}"#)
    let underlying = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "inner"])
    let outer = NSError(domain: "x", code: 2, userInfo: [NSLocalizedDescriptionKey: "outer", NSUnderlyingErrorKey: underlying])
    #expect(json(["err": outer]) ==
        #"{"err":{"type":"NSError","message":"outer","cause":{"type":"NSError","message":"inner"}}}"#)
    #expect(encodeFields(["msg": "two words", "plain": "x", "err": Broken(description: "no")]).map(\.human) ==
        ["no", "\"two words\"", "x"])
}

@Test func scopeVariables() {
    #expect(levelVariable(["api", "auth-v2"]) == "API_AUTH_V2_LOG_LEVEL")
    #expect(LogLevel(parsing: "DEBUG") == .debug)
    #expect(LogLevel(parsing: "loud") == nil)
}

/// Runs `body` with the stream written to a pipe, returning what it wrote.
func capture(_ format: String = "json", _ body: () -> Void) -> String {
    var fds: [Int32] = [0, 0]
    precondition(pipe(&fds) == 0)
    setLogFormat(format)
    setLogOSLog(false)
    setLogService("probe")
    redirect(fds[1])
    body()
    redirect(STDERR_FILENO)
    close(fds[1])
    let data = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true).readDataToEndOfFile()
    return String(decoding: data, as: UTF8.self)
}

func events(_ text: String) -> [[String: Any]] {
    text.split(separator: "\n").map {
        try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
    }
}

// Everything that writes the stream runs in this one suite, one at a time:
// the stream and the setters are the process's.
@Suite(.serialized) struct Stream {
    @Test func spansNest() throws {
        let out = capture {
            log.span("sync", ["repo": "ui"]) { s in
                s.info("cloned", ["files": 3])
                s.span("build") { c in c.warn("slow step") }
                s.set(["pushed": true])
            }
            _ = try? log.span("deploy") { _ -> Void in throw Broken(description: "boom") }
        }
        let e = events(out)
        #expect(e.map { $0["msg"] as! String } == ["sync", "cloned", "build", "slow step", "build", "sync", "deploy", "deploy"])
        #expect(e.map { $0["phase"] as? String } == ["start", nil, "start", nil, "end", "end", "start", "end"])
        let sync = e[0]["span_id"] as! String, build = e[2]["span_id"] as! String
        #expect(e[1]["span_id"] as? String == sync)
        #expect(e[2]["parent_id"] as? String == sync)
        #expect(e[3]["span_id"] as? String == build)
        #expect(Set(e[0..<6].map { $0["trace_id"] as! String }).count == 1)
        #expect(e[6]["trace_id"] as? String != e[0]["trace_id"] as? String)
        #expect(e[5]["fields"] as? [String: AnyHashable] == ["pushed": true, "repo": "ui"])
        #expect(e[7]["status"] as? String == "error" && e[7]["verb"] as? String == "fail" && e[7]["level"] as? String == "error")
        #expect((e[7]["fields"] as! [String: Any])["err"] as? [String: String] == ["type": "Broken", "message": "boom"])
        // Keys in the contract's order.
        #expect(out.split(separator: "\n")[4].hasPrefix(#"{"time":"#))
        #expect(out.split(separator: "\n")[4].contains(#""msg":"build","service":"probe","phase":"end","trace_id":"#))
    }

    @Test func joinContinuesRemote() throws {
        let remote = try Traceparent(parsing: "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01")
        var handed: Traceparent?
        let out = capture {
            log.join(remote.description).span("handle") { s in handed = s.traceparent }
            _ = log.join("garbage")
            _ = log.join("garbage")
            _ = log.join(nil as String?)
        }
        let e = events(out)
        #expect(e[0]["trace_id"] as? String == remote.traceID)
        #expect(e[0]["parent_id"] as? String == remote.spanID)
        #expect(handed?.traceID == remote.traceID && handed?.spanID == e[0]["span_id"] as? String)
        // A malformed value is warned about once, then ignored.
        #expect(e.filter { $0["msg"] as? String == "malformed traceparent ignored" }.count == 1)
    }

    @Test func hiddenSpanAnchorsToShownAncestor() {
        setenv("QUIET_LOG_LEVEL", "warn", 1)
        defer { unsetenv("QUIET_LOG_LEVEL") }
        let out = capture {
            let outer = log.begin("outer")
            let quiet = outer.scope("quiet").begin("child")
            // Hidden: what it holds belongs to the shown span above it.
            #expect(quiet.traceparent == outer.traceparent)
            quiet.warn("inside")
            quiet.end(Broken(description: "lost?"))
            outer.end()
            // A hidden root with no shown ancestor hands on its own id, and
            // its lines carry no ids at all.
            let root = log.scope("quiet").begin("alone")
            #expect(root.traceparent.spanID == root.spanID)
            root.warn("bare")
            root.end()
        }
        let e = events(out)
        #expect(e.map { $0["msg"] as! String } == ["outer", "inside", "child", "outer", "bare"])
        let outerID = e[0]["span_id"] as! String
        #expect(e[1]["span_id"] as? String == outerID)
        // Its failure is never lost: a fail line in the shown span, no phase.
        #expect(e[2]["verb"] as? String == "fail" && e[2]["phase"] == nil && e[2]["span_id"] as? String == outerID)
        #expect((e[2]["fields"] as! [String: Any])["dur_ms"] is Double)
        #expect(e[4]["span_id"] == nil && e[4]["trace_id"] == nil)
    }

    @Test func levelsOffBuildNothing() {
        var built = false
        func expensive() -> Fields {
            built = true
            return [:]
        }
        let out = capture {
            log.debug("never", expensive())
            log.trace("never", expensive())
        }
        #expect(out.isEmpty && !built)
    }

    @Test func humanRendering() {
        let out = capture("human") {
            log.scope("api").warn("upstream returned 502", ["status": 502])
            log.span("sync") { s in
                s.info("cloned", ["files": 3])
                s.span("build") { c in c.step("compile") }
            }
        }
        let lines = out.split(separator: "\n").map(String.init)
        #expect(lines[0] == "⚠ [api] upstream returned 502 status=502")
        #expect(lines[1] == "○ sync")
        #expect(lines[2] == "    cloned files=3")
        #expect(lines[3] == "  ○ build")
        #expect(lines[4] == "      • compile")
        #expect(lines[5].hasPrefix("  ✓ build ") && lines[5].hasSuffix("ms"))
        #expect(lines[6].hasPrefix("✓ sync "))
    }
}
