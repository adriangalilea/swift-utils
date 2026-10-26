#if os(macOS)
    import Darwin
    import Foundation
    import Log
    import Synchronization

    let onePasswordLog = log.scope("onepassword")

    /// 1Password's command line, `op`, the one way an app runs it. `op` lives
    /// in folders any program of the user can write to, so what is found
    /// there is never trusted: it starts suspended, holding its environment
    /// (a token included) and its stdin but having run nothing, its running
    /// code is checked against `signedBy` (AgileBits' Developer ID), and only
    /// then does it run. Anything else is killed before its first
    /// instruction. Checking the file first would leave it swappable between
    /// the check and the launch; this checks the process the secret went to.
    ///
    /// It runs as one of two `Mode`s, each with an environment built here and
    /// nothing inherited: a service account (`OP_SERVICE_ACCOUNT_TOKEN`, no
    /// app, no person) or the person's own 1Password app (which asks them).
    /// Secrets travel on its stdin or in its environment for that one run,
    /// never in its arguments, the log or an error.
    ///
    /// The module's one top-level name; everything else is nested here.
    public enum OnePasswordCLI {
        /// Who `op` must be: signed with AgileBits' Developer ID, as
        /// `com.1password.op`.
        static let signedBy =
            #"anchor apple generic and identifier "com.1password.op" and certificate leaf[subject.OU] = "2BUA8C4S2C""#

        /// Where `op` is looked for, in order: Homebrew's (Apple silicon,
        /// then Intel, where 1Password's own installer puts it too), then
        /// each folder of this process's PATH. The first executable wins;
        /// whatever it is, it runs only if AgileBits signed it.
        static var candidates: [String] {
            ["/opt/homebrew/bin/op", "/usr/local/bin/op"]
                + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map {
                    "\($0)/op"
                }
        }

        /// The `op` a run would start (`candidates`, the first executable).
        /// Reading it proves nothing about who made it: `run` does that.
        public static func locate() throws(Failure) -> String {
            let searched = candidates
            guard
                let found = searched.first(where: {
                    FileManager.default.isExecutableFile(atPath: $0)
                })
            else { throw .notInstalled(searched: searched) }
            return found
        }

        /// Runs `op arguments` as `mode`, `input` on its stdin (else
        /// /dev/null), within `timeout`: its stdout once it exits 0.
        /// Everything it prints is read while it runs, so a large output never
        /// stalls it; past `timeout` it is terminated, then killed.
        public static func run(
            _ arguments: [String], as mode: Mode, input: Data? = nil, timeout: Duration
        ) async throws(Failure) -> Data {
            let started = ContinuousClock.now
            let result = await detached {
                Result { () throws(Failure) -> Data in
                    let launch = try Launch(arguments, mode: mode)
                    let child = try launch.spawn(stdin: input == nil ? .null : .pipe, stdout: .pipe)
                    return try child.finish(input: input, timeout: timeout, launch: launch)
                }
            }
            record(arguments, mode: mode, since: started, result.map { _ in () })
            return try result.get()
        }

        /// Starts `op arguments` as `mode` with its stdin and stdout on the
        /// caller's descriptors (pipe ends whose other ends go to someone
        /// else, so what `op` reads and prints never passes through this
        /// process). Checked like every run before it runs; the caller closes
        /// its copies of `stdin` and `stdout` once started. Only its stderr
        /// comes back here, through `Running.wait`, which must be called.
        public static func start(
            _ arguments: [String], as mode: Mode, stdin: Int32, stdout: Int32
        ) throws(Failure) -> Running {
            precondition(stdin >= 0 && stdout >= 0, "start needs two open descriptors")
            let started = ContinuousClock.now
            do {
                let launch = try Launch(arguments, mode: mode)
                let child = try launch.spawn(stdin: .descriptor(stdin), stdout: .descriptor(stdout))
                return Running(
                    child: child, launch: launch, arguments: arguments, mode: mode, started: started
                )
            } catch {
                record(arguments, mode: mode, since: started, .failure(error))
                throw error
            }
        }

        /// An `op` started on the caller's descriptors (`start`).
        public final class Running: Sendable {
            private let child: Child
            private let launch: Launch
            private let arguments: [String]
            private let mode: Mode
            private let started: ContinuousClock.Instant
            private let waited = Flag()

            init(
                child: Child, launch: Launch, arguments: [String], mode: Mode,
                started: ContinuousClock.Instant
            ) {
                self.child = child
                self.launch = launch
                self.arguments = arguments
                self.mode = mode
                self.started = started
            }

            /// Waits for it to exit 0 within `timeout`, else says why. Once:
            /// a second wait is a bug.
            public func wait(timeout: Duration) async throws(Failure) {
                precondition(waited.set(), "Running.wait called twice")
                let result = await detached { [child, launch] in
                    Result { () throws(Failure) -> Void in
                        _ = try child.finish(input: nil, timeout: timeout, launch: launch)
                    }
                }
                record(arguments, mode: mode, since: started, result)
                try result.get()
            }

            deinit {
                // Never waited: a zombie and a leaked descriptor, and a run
                // whose outcome nobody read.
                assert(waited.isSet, "an op started and never waited on")
            }
        }

        /// What a run did, for the log: the words of `op`'s command before the
        /// first flag or secret reference, at most two ("item create",
        /// "read"), else the first flag ("--version"). Never a ref, never a
        /// name typed after the command.
        static func verb(_ arguments: [String]) -> String {
            let words = arguments.prefix { !$0.hasPrefix("-") && !$0.contains("://") }.prefix(2)
            if !words.isEmpty { return words.joined(separator: " ") }
            return arguments.first.flatMap { $0.hasPrefix("-") ? $0 : nil } ?? "op"
        }

        /// One line per run: verb, mode, duration, outcome. Fields only.
        private static func record(
            _ arguments: [String], mode: Mode, since started: ContinuousClock.Instant,
            _ result: Result<Void, Failure>
        ) {
            let fields: Fields = [
                "verb": verb(arguments), "mode": mode.access.rawValue,
                "ms": started.duration(to: .now),
            ]
            switch result {
            case .success: onePasswordLog.info("op", fields.merging(["outcome": "ok"]) { $1 })
            case .failure(let failure):
                onePasswordLog.warn("op", fields.merging(["outcome": failure.name]) { $1 })
            }
        }

        /// Blocking work on a thread of its own, never the cooperative pool:
        /// a run blocks on pipes and `waitpid` for as long as `op` takes.
        private static func detached<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
            await withCheckedContinuation { done in
                Thread.detachNewThread { done.resume(returning: body()) }
            }
        }
    }

    /// Set once, read from any thread.
    final class Flag: Sendable {
        private let value = Mutex(false)
        /// True the first time only.
        func set() -> Bool {
            value.withLock { was in
                defer { was = true }
                return !was
            }
        }
        var isSet: Bool { value.withLock { $0 } }
    }
#endif
