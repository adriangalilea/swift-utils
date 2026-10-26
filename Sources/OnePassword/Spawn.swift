#if os(macOS)
    import Darwin
    import Foundation
    import Security

    extension OnePasswordCLI {
        /// One run, fixed before anything starts: which executable, its argv,
        /// its whole environment, who must have signed it, and what is secret
        /// in it (for `Failure.redacted`).
        struct Launch: Sendable {
            let path: String
            let arguments: [String]
            let environment: [String: String]
            let requirement: String
            let access: Mode.Access
            let token: String?

            /// `op` as `mode`: located, its home made, signed by AgileBits.
            init(_ arguments: [String], mode: Mode) throws(Failure) {
                let path = try OnePasswordCLI.locate()
                do {
                    try FileManager.default.createDirectory(
                        at: mode.home, withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700])
                } catch {
                    throw .couldNotStart(
                        path: path, why: "its home \(mode.home.path): \(error.localizedDescription)"
                    )
                }
                self.init(
                    path: path, arguments: arguments, environment: mode.environment,
                    requirement: OnePasswordCLI.signedBy, access: mode.access, token: mode.token)
            }

            /// Any executable under any requirement: the tests' door (an Apple
            /// tool under Apple's requirement proves the plumbing; under
            /// AgileBits' it proves the refusal).
            init(
                path: String, arguments: [String], environment: [String: String],
                requirement: String,
                access: Mode.Access, token: String?
            ) {
                self.path = path
                self.arguments = arguments
                self.environment = environment
                self.requirement = requirement
                self.access = access
                self.token = token
            }

            enum Stdin {
                case null
                case pipe
                case descriptor(Int32)
            }
            enum Stdout {
                case pipe
                case descriptor(Int32)
            }

            /// Spawned suspended with every descriptor but 0, 1 and 2 closed
            /// and default signal handling, its running code checked against
            /// `requirement` through its audit token (which names this one
            /// process, never a later one with its pid), then resumed; anything
            /// else is killed and reaped before its first instruction.
            func spawn(stdin: Stdin, stdout: Stdout) throws(Failure) -> Child {
                var required: SecRequirement?
                let compiled = SecRequirementCreateWithString(
                    requirement as CFString, [], &required)
                precondition(
                    compiled == errSecSuccess && required != nil,
                    "requirement does not compile: \(requirement)")

                // Every descriptor this function opens, closed on any way out
                // except the ends handed to the child's owner.
                var opened: [Int32] = []
                func newPipe() throws(Failure) -> (read: Int32, write: Int32) {
                    var ends: [Int32] = [-1, -1]
                    guard pipe(&ends) == 0 else {
                        let code = errno
                        opened.forEach { close($0) }
                        throw .couldNotStart(
                            path: path, why: "no pipe: \(String(cString: strerror(code)))")
                    }
                    for end in ends { _ = fcntl(end, F_SETFD, FD_CLOEXEC) }
                    opened += ends
                    return (ends[0], ends[1])
                }
                let inPipe: (read: Int32, write: Int32)? =
                    if case .pipe = stdin { try newPipe() } else { nil }
                let outPipe: (read: Int32, write: Int32)? =
                    if case .pipe = stdout { try newPipe() } else { nil }
                let errPipe = try newPipe()

                var actions: posix_spawn_file_actions_t?
                posix_spawn_file_actions_init(&actions)
                defer { posix_spawn_file_actions_destroy(&actions) }
                switch stdin {
                case .null: posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
                case .pipe: posix_spawn_file_actions_adddup2(&actions, inPipe!.read, 0)
                case .descriptor(let given): posix_spawn_file_actions_adddup2(&actions, given, 0)
                }
                switch stdout {
                case .pipe: posix_spawn_file_actions_adddup2(&actions, outPipe!.write, 1)
                case .descriptor(let given): posix_spawn_file_actions_adddup2(&actions, given, 1)
                }
                posix_spawn_file_actions_adddup2(&actions, errPipe.write, 2)

                var attributes: posix_spawnattr_t?
                posix_spawnattr_init(&attributes)
                defer { posix_spawnattr_destroy(&attributes) }
                // Suspended until checked; every descriptor not named above
                // closed; every signal at its default and none blocked, so a
                // timeout's SIGTERM reaches it whatever this process ignores.
                var everySignal = sigset_t()
                sigfillset(&everySignal)
                var noSignal = sigset_t()
                sigemptyset(&noSignal)
                posix_spawnattr_setsigdefault(&attributes, &everySignal)
                posix_spawnattr_setsigmask(&attributes, &noSignal)
                posix_spawnattr_setflags(
                    &attributes,
                    Int16(
                        POSIX_SPAWN_START_SUSPENDED | POSIX_SPAWN_CLOEXEC_DEFAULT
                            | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

                let argv = ([path] + arguments).map { strdup($0) } + [nil]
                let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
                defer {
                    argv.forEach { free($0) }
                    // The environment may hold a token: zeroed before freed.
                    envp.forEach { entry in
                        if let entry { memset_s(entry, strlen(entry), 0, strlen(entry)) }
                        free(entry)
                    }
                }
                var pid: pid_t = 0
                let spawned = posix_spawn(&pid, path, &actions, &attributes, argv, envp)
                // The child's ends are the child's now.
                for end in [inPipe?.read, outPipe?.write, errPipe.write].compactMap({ $0 }) {
                    close(end)
                    opened.removeAll { $0 == end }
                }
                guard spawned == 0 else {
                    opened.forEach { close($0) }
                    throw .couldNotStart(path: path, why: String(cString: strerror(spawned)))
                }

                if let refused = Self.verify(pid, against: required!) {
                    kill(pid, SIGKILL)
                    var ended: Int32 = 0
                    waitpid(pid, &ended, 0)
                    opened.forEach { close($0) }
                    throw .notAgileBits(path: path, why: refused)
                }
                kill(pid, SIGCONT)
                return Child(
                    pid: pid, stdin: inPipe?.write, stdout: outPipe?.read, stderr: errPipe.read)
            }

            /// Nil when the suspended process `pid` (our unreaped child) runs
            /// code satisfying `required`; else why not.
            static func verify(_ pid: pid_t, against required: SecRequirement) -> String? {
                var task: mach_port_name_t = 0
                let named = task_name_for_pid(mach_task_self_, pid, &task)
                guard named == KERN_SUCCESS else {
                    return "its task could not be named (kern_return \(named))"
                }
                defer { mach_port_deallocate(mach_task_self_, task) }
                var token = audit_token_t()
                var count = mach_msg_type_number_t(
                    MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size)
                let read = withUnsafeMutablePointer(to: &token) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                        task_info(task, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
                    }
                }
                guard read == KERN_SUCCESS else {
                    return "its audit token could not be read (kern_return \(read))"
                }
                // The token's sixth word is its pid: the process asked about.
                guard token.val.5 == UInt32(bitPattern: pid) else {
                    return "its audit token names another process"
                }
                let audit = withUnsafeBytes(of: &token) { Data($0) }
                var code: SecCode?
                var status = SecCodeCopyGuestWithAttributes(
                    nil, [kSecGuestAttributeAudit: audit] as CFDictionary, [], &code)
                if status == errSecSuccess, let code {
                    status = SecCodeCheckValidity(code, [], required)
                }
                guard status == errSecSuccess else {
                    let said =
                        SecCopyErrorMessageString(status, nil).map { $0 as String }
                        ?? "OSStatus \(status)"
                    return "its code signature does not satisfy AgileBits' requirement: \(said)"
                }
                return nil
            }
        }

        /// A started, checked, resumed `op` and this process's ends of its
        /// pipes. Reaped by `finish`, exactly once.
        struct Child: Sendable {
            let pid: pid_t
            let stdin: Int32?
            let stdout: Int32?
            let stderr: Int32

            /// Feeds `input` to its stdin (closed after, so `op` sees its end),
            /// drains its stdout and stderr, and reaps it, all at once and on
            /// threads of their own, so neither side ever waits on a full pipe.
            /// Bounded by `timeout`: past it, SIGTERM, then SIGKILL two seconds
            /// later. Its stdout once it exits 0.
            func finish(input: Data?, timeout: Duration, launch: Launch) throws(Failure) -> Data {
                precondition((input == nil) == (stdin == nil), "input and a stdin pipe go together")
                let ran = Ran()
                let drained = DispatchGroup()
                if let stdin, let input {
                    drained.enter()
                    Thread.detachNewThread {
                        ran.fed = Self.feed(input, to: stdin)
                        drained.leave()
                    }
                }
                for (descriptor, keep) in [(stdout, true), (stderr, false)] {
                    guard let descriptor else { continue }
                    drained.enter()
                    Thread.detachNewThread {
                        let read = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                            .readDataToEndOfFile()
                        if keep { ran.output = read } else { ran.errors = read }
                        drained.leave()
                    }
                }
                let exited = DispatchSemaphore(value: 0)
                Thread.detachNewThread {
                    var status: Int32 = 0
                    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
                    ran.status = status
                    exited.signal()
                }
                let deadline = DispatchTime.now() + .nanoseconds(Int(timeout.nanoseconds))
                guard exited.wait(timeout: deadline) == .success else {
                    // Only our unreaped child can hold this pid: the waiter
                    // above reaps it once it dies.
                    kill(pid, SIGTERM)
                    if exited.wait(timeout: .now() + 2) == .timedOut {
                        kill(pid, SIGKILL)
                        exited.wait()
                    }
                    throw .timedOut(after: timeout)
                }
                // Something `op` started can hold its pipes past its exit: the
                // same deadline bounds them.
                guard drained.wait(timeout: deadline) == .success else {
                    throw .timedOut(after: timeout)
                }

                // A normal exit: the low seven bits are zero, the code is the next byte.
                let signal = ran.status & 0x7f
                let code = (ran.status >> 8) & 0xff
                guard signal == 0, code == 0 else {
                    let said = Failure.cleaned(ran.errors, token: launch.token, input: input)
                    guard !said.isEmpty else {
                        throw .failed(
                            said: signal == 0
                                ? "op exited \(code)" : "op was killed by signal \(signal)")
                    }
                    throw Failure.reading(said, access: launch.access)
                }
                guard ran.fed else {
                    throw .failed(said: "op exited before reading all of its input")
                }
                return ran.output
            }

            /// Writes all of `input` to `descriptor`, then closes it. False
            /// when `op` closed its end first (EPIPE, raised as an error here
            /// and never as SIGPIPE to this process).
            static func feed(_ input: Data, to descriptor: Int32) -> Bool {
                defer { close(descriptor) }
                _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
                return input.withUnsafeBytes { bytes in
                    var sent = 0
                    while sent < bytes.count {
                        let wrote = write(descriptor, bytes.baseAddress! + sent, bytes.count - sent)
                        if wrote < 0 {
                            if errno == EINTR { continue }
                            return false
                        }
                        sent += wrote
                    }
                    return true
                }
            }
        }

        /// What one run left: each field written by exactly one thread and
        /// read only after waiting on that thread (the group or the
        /// semaphore), which orders the write before the read.
        private final class Ran: @unchecked Sendable {
            var output = Data()
            var errors = Data()
            var status: Int32 = 0
            var fed = true
        }
    }

    extension Duration {
        fileprivate var nanoseconds: Int64 {
            components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
        }
    }
#endif
