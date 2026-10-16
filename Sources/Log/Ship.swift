import Foundation
import Synchronization

// Shipping: with LOG_SHIP set (or setLogShip), every event that passes its
// threshold is also POSTed there as the stream's JSON line, whatever stderr
// renders. A batch is lines joined by "\n", Content-Type
// text/plain;charset=utf-8, at most 64 KB and 50 events, LOG_SHIP_TOKEN (or
// setLogShipToken) its bearer. It leaves 2s after its first event, at 50
// events, when a span opened outside any span of this process ends (so a
// request's trace leaves together), and at exit: the first shipped event
// hooks atexit, which waits for what is in flight. A process that leaves
// another way (exec, _exit, a signal) calls flushLog first. Shipping never
// blocks a write and never throws: a refused or lost batch is one warnOnce,
// scope ["ship"], and an event over 64 KB stays on stderr and warns once.

/// navigator.sendBeacon's ceiling, the contract's for every writer.
let shipMaxBytes = 64 * 1024
private let shipMaxEvents = 50
private let shipAfter: DispatchTimeInterval = .seconds(2)
/// A collector that hangs costs flushLog this much, then one warning.
private let shipTimeout: TimeInterval = 10

let shipLog = LogWriter().scope("ship")

/// Where events are also POSTed, an http(s) URL; LOG_SHIP overrides it.
public func setLogShip(_ url: String) {
    let parsed = parseShip("setLogShip", url)
    settings.withLock { $0.ship = parsed }
}

/// The bearer sent with each batch; LOG_SHIP_TOKEN overrides it.
public func setLogShipToken(_ token: String) {
    precondition(!token.isEmpty, "setLogShipToken: want a non-empty token")
    settings.withLock { $0.shipToken = token }
}

private func parseShip(_ source: String, _ value: String) -> String {
    guard let url = URL(string: value), url.scheme == "http" || url.scheme == "https", url.host != nil
    else { fatalError("\(source): unknown URL \"\(value)\" (want an http(s) URL)") }
    return value
}

func shipTarget() -> String? {
    if let value = env("LOG_SHIP") { return parseShip("LOG_SHIP", value) }
    return settings.withLock { $0.ship }
}

private func shipToken() -> String? {
    env("LOG_SHIP_TOKEN") ?? settings.withLock { $0.shipToken }
}

private struct Batch {
    let target: String
    let generation: Int
    var lines: [String] = []
    /// UTF-8 bytes of the lines joined by "\n".
    var size = -1
}

private struct Shipping {
    var batch: Batch? = nil
    var generation = 0
    var hooked = false
}

private let shipping = locked(Shipping())
/// One enter per batch being POSTed, one leave when its answer is read.
private let inflight = DispatchGroup()

/// Adds one JSON line to the waiting batch, first sending the batch it would
/// not fit in. Called under the output lock, so a batch keeps stderr's
/// order. False: the line alone is over the ceiling and is not shipped.
func ship(_ target: String, _ line: String) -> Bool {
    let size = line.utf8.count
    if size > shipMaxBytes { return false }
    let hook = shipping.withLock { s -> Bool in
        if let b = s.batch, b.target != target || b.size + 1 + size > shipMaxBytes {
            sendLocked(&s)
        }
        if s.batch == nil {
            s.generation += 1
            let generation = s.generation
            s.batch = Batch(target: target, generation: generation)
            // The timer sends this batch only: one sent earlier is gone.
            DispatchQueue.global().asyncAfter(deadline: .now() + shipAfter) {
                shipping.withLock { s in
                    if s.batch?.generation == generation { sendLocked(&s) }
                }
            }
        }
        s.batch!.lines.append(line)
        s.batch!.size += 1 + size
        if s.batch!.lines.count >= shipMaxEvents { sendLocked(&s) }
        let first = !s.hooked
        s.hooked = true
        return first
    }
    if hook {
        // Hooked on the first shipped event, so linking the logger costs nothing.
        atexit { flushLog() }
    }
    return true
}

/// Sends the waiting batch, if any, without waiting for its answer.
func send() {
    shipping.withLock { sendLocked(&$0) }
}

private func sendLocked(_ s: inout Shipping) {
    guard let b = s.batch else { return }
    s.batch = nil
    inflight.enter()
    post(b)
}

/// POSTs one batch. Any answer but 204 is a refused batch, warned about once
/// before the batch counts as answered, so flushLog ships the warning too.
private func post(_ b: Batch) {
    var request = URLRequest(url: URL(string: b.target)!, timeoutInterval: shipTimeout)
    request.httpMethod = "POST"
    request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
    if let token = shipToken() {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = Data(b.lines.joined(separator: "\n").utf8)
    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { inflight.leave() }
        if let error {
            shipLog.warnOnce("log batch not delivered", ["err": error])
            return
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 204 {
            let answer = String(decoding: (data ?? Data()).prefix(1000), as: UTF8.self)
            shipLog.warnOnce("log batch refused", ["status": status, "answer": answer])
        }
    }.resume()
}

/// Sends what waits to LOG_SHIP and returns once no batch is in flight.
/// Runs at exit by itself; a process leaving through exec, _exit or a signal
/// calls it first. A refused batch's warning is an event too: it ships
/// before this returns.
public func flushLog() {
    while true {
        send()
        inflight.wait()
        if shipping.withLock({ $0.batch == nil }) { return }
    }
}
