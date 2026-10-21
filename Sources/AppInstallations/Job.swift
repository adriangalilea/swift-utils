#if os(macOS)
    import AppKit
    import ServiceManagement

    extension AppInstallation {
        /// A process the app runs beside itself through `SMAppService`, the
        /// app's own job: a launch agent, a root daemon, or the app as its
        /// login item. Declared once, by name, like a permission:
        ///
        ///     extension AppInstallation.Job {
        ///         static let chilld = AppInstallation.Job(
        ///             .daemon(plist: "garden.untitled.chilld.plist"), name: "chilld",
        ///             answers: { (try? Client().hello()) != nil })
        ///     }
        ///     try await AppInstallation.Job.chilld.install()
        ///
        /// `answers` is the truth about running: BTM's `.enabled` says the
        /// job is registered and approved, never that launchd runs it. By
        /// default launchd is asked (`launchctl print`: state running); an
        /// app that can ask the job itself (an XPC ping, a socket, with its
        /// own short timeout) passes that, the stronger witness.
        public struct Job: Sendable {
            public enum Kind: Hashable, Sendable {
                /// `Contents/Library/LaunchAgents/<plist>`, runs as the person.
                case agent(plist: String)
                /// `Contents/Library/LaunchDaemons/<plist>`, runs as root;
                /// approving it is an admin's act.
                case daemon(plist: String)
                /// The app itself, opened at login.
                case loginItem
            }

            public let kind: Kind
            /// What logs and words call it ("chilld", "awake's agent").
            public let name: String
            let answers: (@Sendable () -> Bool)?

            public init(_ kind: Kind, name: String, answers: (@Sendable () -> Bool)? = nil) {
                self.kind = kind
                self.name = name
                self.answers = answers
            }

            /// The app as its own login item.
            public static let loginItem = Job(.loginItem, name: "the login item")

            /// The installs this job runs from. A root daemon only from an
            /// install for everyone: from a folder the person can write to,
            /// replacing its binary would run anyone's code as root. An
            /// agent or a login item runs as the person, from either.
            public var scopes: Set<Scope> {
                if case .daemon = kind { return [.everyone] }
                return Set(Scope.allCases)
            }

            var service: SMAppService {
                switch kind {
                case .agent(let plist): .agent(plistName: plist)
                case .daemon(let plist): .daemon(plistName: plist)
                case .loginItem: .mainApp
                }
            }

            /// The job's plist inside the bundle, for an agent or a daemon.
            var plistPath: String? {
                switch kind {
                case .agent(let name): "Contents/Library/LaunchAgents/\(name)"
                case .daemon(let name): "Contents/Library/LaunchDaemons/\(name)"
                case .loginItem: nil
                }
            }

            /// The launchd label, read from the bundled plist.
            var label: String? {
                guard let plistPath, let bundle = AppInstallation.bundle,
                    let plist = NSDictionary(contentsOf: bundle.appending(path: plistPath))
                else { return nil }
                return plist["Label"] as? String
            }

            // MARK: State

            /// Where the job stands, read now: the one answer every surface
            /// and every verb renders.
            public enum State: Equatable, Sendable {
                case running
                /// Installable and not installed (a login item: off).
                case off
                /// Registered, held for the person's OK in Login Items. A
                /// daemon held for a person who is not an admin needs one.
                case awaitingApproval(needsAdmin: Bool)
                /// Registered and approved, and not answering here: stopped,
                /// or registered for another copy of the app (one that moved
                /// or was replaced; launchd keeps starting the image the record
                /// names, never the copy that moved).
                case silent
                /// The app runs from somewhere this job cannot (`scopes`).
                case misplaced(Home)
                /// This build has no such job (no plist in the bundle).
                case bare(missing: String)
            }

            public var state: State {
                if let plistPath {
                    guard let bundle = AppInstallation.bundle else {
                        return .bare(missing: "an app bundle")
                    }
                    guard
                        FileManager.default.fileExists(
                            atPath: bundle.appending(path: plistPath).path)
                    else { return .bare(missing: plistPath) }
                }
                // A job lives with the installed app, so the place is judged
                // before anything macOS remembers: a record can outlive the
                // copy it was made for (a deleted app's stays enabled), and
                // reading it from a copy elsewhere would offer to restart the
                // job from there.
                let home = AppInstallation.home
                guard case .installed(let scope) = home, scopes.contains(scope) else {
                    return .misplaced(home)
                }
                switch service.status {
                case .enabled:
                    if case .loginItem = kind { return .running }
                    // Judged before the probe: the other copy's process may
                    // answer it, and still not be this copy's job.
                    if registeredElsewhere { return .silent }
                    return (answers ?? launchdRuns)() ? .running : .silent
                case .requiresApproval:
                    if case .daemon = kind {
                        return .awaitingApproval(needsAdmin: !Self.userIsAdmin)
                    }
                    return .awaitingApproval(needsAdmin: false)
                case .notRegistered, .notFound:
                    return .off
                @unknown default:
                    return .off
                }
            }

            /// System Settings' own words for where approval happens.
            public static let approvalPath = "System Settings › General › Login Items & Extensions"

            /// The state in a terminal's words, for an app's command line.
            public var words: String {
                switch state {
                case .running: "running"
                case .off: kind == .loginItem ? "off" : "not installed"
                case .awaitingApproval(let needsAdmin):
                    "awaiting approval in \(Self.approvalPath)"
                        + (needsAdmin ? " (an admin's act)" : "")
                case .silent:
                    registeredElsewhere
                        ? "registered for another copy of the app (moved or replaced)"
                        : "registered, but not answering"
                case .misplaced(let home): "running from \(home.words); \(needs)"
                case .bare(let missing): "not part of this build (no \(missing))"
                }
            }

            /// Where the job needs the app, in words.
            var needs: String {
                scopes == [.everyone]
                    ? "\(name) runs only from an install for everyone (/Applications)"
                    : "\(name) runs only from an Applications folder"
            }

            // MARK: Verbs

            public enum Failure: Error, CustomStringConvertible, Equatable {
                case misplaced(Home, needs: String)
                case bare(missing: String)
                /// macOS refused the registration, with its reason.
                case register(String)
                /// Still held for approval when the wait ran out.
                case awaitingApproval(needsAdmin: Bool)
                /// Registered afresh and approved, and still not answering.
                case silent

                public var description: String {
                    switch self {
                    case .misplaced(let home, let needs): "running from \(home.words): \(needs)"
                    case .bare(let missing): "not part of this build (no \(missing))"
                    case .register(let why): "macOS refused the registration: \(why)"
                    case .awaitingApproval(let needsAdmin):
                        "still awaiting approval in \(Job.approvalPath)"
                            + (needsAdmin ? "; approving it needs an admin" : "")
                    case .silent:
                        "registered and approved, but not answering; its log says why"
                    }
                }
            }

            /// Installs it and waits until it runs: registers (retried while
            /// macOS settles), opens Login Items once when it needs the
            /// person's OK and waits up to `approvalWait` for it, then waits
            /// for it to answer; on but silent here, it is unregistered first
            /// and registered afresh for this copy.
            /// Idempotent: a running job returns at once. One install per job
            /// at a time in the process: a second caller (a press while the
            /// launch turns the job on) joins the one in flight, because its
            /// silent branch unregisters, which would stop a job the first
            /// had just started.
            @discardableResult
            public func install(approvalWait: Duration = .seconds(60)) async throws -> State {
                try await install(approvalWait: approvalWait, afresh: false)
            }

            /// `afresh`: a witness says the registration is stale whatever it
            /// reads now (the old copy's job, whose image moved away, still
            /// answers until it is stopped), so it is registered afresh.
            @discardableResult
            func install(approvalWait: Duration, afresh: Bool) async throws -> State {
                try await InstallFlights.shared.run(handoff) {
                    try await performInstall(approvalWait: approvalWait, afresh: afresh)
                }
            }

            private func performInstall(approvalWait: Duration, afresh: Bool) async throws -> State
            {
                let before: State = afresh && service.status == .enabled ? .silent : state
                switch before {
                case .running: return .running
                case .misplaced(let home): throw Failure.misplaced(home, needs: needs)
                case .bare(let missing): throw Failure.bare(missing: missing)
                case .off, .awaitingApproval, .silent: break
                }
                removeStrayDefinition()
                if before == .silent {
                    // On and not answering here: the record is useless as it
                    // stands (made for another copy, or loaded and stuck, or
                    // dropped by launchd), and registering over it only says
                    // "already registered". Unregistering first is the one fix
                    // for all three; it also stops another copy's process.
                    installLog.info(
                        registeredElsewhere
                            ? "registered for another copy: moving the registration here"
                            : "on but not answering: registering afresh",
                        ["job": name])
                    try? await service.unregister()
                }
                try await register()
                try await awaitApproval(within: approvalWait)
                if case .loginItem = kind { return .running }
                guard await Self.answering(answers ?? launchdRuns) else { throw Failure.silent }
                return .running
            }

            /// Off: unregistered, idempotent (a job not registered is already
            /// the goal). Unregistering a daemon stops it without a SIGTERM,
            /// so what it must hand back happens before (chill: fans to Apple).
            public func uninstall() throws {
                let status = service.status
                guard status == .enabled || status == .requiresApproval else { return }
                do {
                    try service.unregister()
                    installLog.info("uninstalled", ["job": name])
                } catch let error as NSError where error.code == kSMErrorJobNotFound {
                    return
                } catch {
                    throw Failure.register(error.localizedDescription)
                }
            }

            /// An agent running this bundle's image now: `launchctl kickstart
            /// -k`. A daemon restarts itself into a new image (`ImageWatch`);
            /// nothing outside root can kickstart it.
            public func restart() {
                guard case .agent = kind, let label else {
                    preconditionFailure("\(name): only an agent is restarted from outside")
                }
                let result = AppInstallation.launchctl([
                    "kickstart", "-k", "gui/\(getuid())/\(label)",
                ])
                installLog.info("restarted", ["job": name, "status": result])
            }

            /// The installs in flight, one per job (by `handoff`), so a second
            /// caller awaits the first's outcome instead of racing it.
            private actor InstallFlights {
                static let shared = InstallFlights()
                private var running: [String: Task<State, Error>] = [:]

                func run(
                    _ key: String, _ body: @escaping @Sendable () async throws -> State
                ) async throws -> State {
                    if let flight = running[key] { return try await flight.value }
                    let flight = Task { try await body() }
                    running[key] = flight
                    defer { running[key] = nil }
                    return try await flight.value
                }
            }

            /// How a job crosses into a new copy of the app: its plist, or
            /// the login item's own word.
            var handoff: String {
                switch kind {
                case .agent(let plist), .daemon(let plist): plist
                case .loginItem: "login-item"
                }
            }

            /// The launch argument naming a job the new copy turns on
            /// (`moveHome(to:turningOn:)`).
            static let turnOnArgument = "--app-installation-turn-on"

            /// The launch argument naming a job whose old copy moved away: its
            /// old process (the witness) opens the moved copy with it, and the
            /// copy registers the job afresh and exits, no window shown.
            static let staleArgument = "--app-installation-stale"

            /// Every agent and daemon `bundle` declares (its LaunchAgents and
            /// LaunchDaemons plists), the app's own declaration standing in
            /// for the plist it names (its probe, the stronger witness).
            static func declared(in bundle: URL, own: [Job] = []) -> [Job] {
                let mine = Dictionary(own.map { ($0.handoff, $0) }, uniquingKeysWith: { a, _ in a })
                return ["LaunchAgents", "LaunchDaemons"].flatMap { folder in
                    let names =
                        (try? FileManager.default.contentsOfDirectory(
                            atPath: bundle.appending(path: "Contents/Library/\(folder)").path))
                        ?? []
                    return names.filter { $0.hasSuffix(".plist") }.map { plist in
                        mine[plist]
                            ?? Job(
                                folder == "LaunchAgents"
                                    ? .agent(plist: plist) : .daemon(plist: plist),
                                name: plist)
                    }
                }
            }

            /// The person's choice kept across copies of the app, run by the
            /// app at launch (`ImageWatch.start`), off the main thread. For
            /// each job this bundle declares, and the login item:
            ///
            /// - Named stale (`staleArgument`, by its old copy's process,
            ///   which saw its image move away): registered afresh, whatever
            ///   it reads, since that old process still answers until stopped.
            /// - Asked for by the copy that moved here (`turnOnArgument`,
            ///   `moveHome(to:turningOn:)`): installed now, the OS's approval
            ///   included: one press, the job working.
            /// - On yet not answering here (`.silent`: the record was made for
            ///   a copy that moved, was replaced or was deleted): registered
            ///   afresh, so the person who turned it on need not again.
            ///
            /// A job turned off is never touched, nor one held for approval; a
            /// name this copy does not declare is logged and ignored; one
            /// still silent after this is a real failure and reads as one.
            static func settle(in bundle: URL, own: [Job], arguments: [String]) async {
                func named(_ flag: String) -> Set<String> {
                    Set(
                        arguments.indices.dropLast().filter { arguments[$0] == flag }
                            .map { arguments[$0 + 1] })
                }
                let asked = named(turnOnArgument)
                let stale = named(staleArgument)
                let all = declared(in: bundle, own: own) + [.loginItem]
                for stranger in asked.union(stale).subtracting(all.map(\.handoff)) {
                    installLog.warn(
                        "named a job this copy does not declare; ignored", ["job": stranger])
                }
                for job in all {
                    let afresh = stale.contains(job.handoff)
                    let why: String
                    if afresh {
                        why = "its old copy moved away: registering afresh here"
                    } else if asked.contains(job.handoff) {
                        why = "turning on, as asked before the move"
                    } else if job.state == .silent {
                        why = "on, but not answering from this copy: registering afresh"
                    } else {
                        continue
                    }
                    installLog.info(why, ["job": job.name])
                    do {
                        try await job.install(approvalWait: .seconds(60), afresh: afresh)
                    } catch {
                        installLog.warn("could not turn on", ["job": job.name, "err": error])
                    }
                }
            }

            // MARK: Internals

            /// launchd's own answer: the job loaded and running (`launchctl
            /// print` in its domain: the person's for an agent, the system's
            /// for a daemon, readable without root).
            var launchdRuns: @Sendable () -> Bool {
                let target = launchdTarget
                return {
                    guard let target else { return false }
                    return AppInstallation.launchctlOutput(["print", target])
                        .contains("\tstate = running")
                }
            }

            /// The job in launchd's own address: the person's domain for an
            /// agent, the system's for a daemon.
            var launchdTarget: String? {
                guard let label else { return nil }
                if case .daemon = kind {
                    return AppInstallation.launchdTarget(label: label, daemon: true)
                }
                return AppInstallation.launchdTarget(label: label, daemon: false)
            }

            /// The job belongs to another copy of the app, whatever launchd
            /// says of its health: the process launchd runs for it lives
            /// outside this copy, or launchd's record names an image outside
            /// it. launchd follows the bundle it registered, not the path
            /// (measured: after a replace-style upgrade, old bundle to the
            /// Trash and the new one copied in, the job restarted from the
            /// copy in the Trash, running the old code silently; after a
            /// move, it respawned from the vanished path and failed,
            /// EX_CONFIG, forever). Only registering from this copy binds it
            /// here.
            var registeredElsewhere: Bool {
                guard let target = launchdTarget, let bundle = AppInstallation.bundle else {
                    return false
                }
                let here = bundle.resolvingSymlinksInPath().path + "/"
                let outside = { (image: String) in
                    !URL(filePath: image).resolvingSymlinksInPath().path.hasPrefix(here)
                }
                if let pid = AppInstallation.launchdPID(target),
                    let image = AppInstallation.image(of: pid)
                {
                    return outside(image)
                }
                return AppInstallation.registeredImage(target).map(outside) ?? false
            }

            /// Registering right after an unregister fails until BTM settles
            /// (EPERM, for seconds: awake learned a second was not always
            /// enough), so a failure is retried; a bad signature never settles.
            private func register() async throws {
                var last: Error?
                for attempt in 0..<6 {
                    if attempt > 0 { try await Task.sleep(for: .seconds(1)) }
                    do {
                        try service.register()
                        installLog.info(
                            "registered", ["job": name, "status": service.status.rawValue])
                        return
                    } catch let error as NSError where error.code == kSMErrorAlreadyRegistered {
                        return
                    } catch let error as NSError where error.code == kSMErrorInvalidSignature {
                        throw Failure.register(
                            "\(error.localizedDescription) (SMAppService needs the bundle signed by a team, never ad hoc)"
                        )
                    } catch {
                        last = error
                    }
                }
                throw Failure.register(last?.localizedDescription ?? "unknown")
            }

            private func awaitApproval(within wait: Duration) async throws {
                let deadline = ContinuousClock.now + wait
                var told = false
                while service.status == .requiresApproval {
                    if !told {
                        installLog.info("awaiting approval: opened Login Items", ["job": name])
                        SMAppService.openSystemSettingsLoginItems()
                        told = true
                    }
                    guard ContinuousClock.now < deadline else {
                        throw Failure.awaitingApproval(
                            needsAdmin: kind != .loginItem && !Self.userIsAdmin)
                    }
                    try await Task.sleep(for: .milliseconds(500))
                }
                guard service.status == .enabled else {
                    throw Failure.register("status \(service.status.rawValue) after registering")
                }
            }

            /// launchd boots a job after approval: up to ten seconds to answer.
            private static func answering(_ answers: @escaping @Sendable () -> Bool) async -> Bool {
                let deadline = ContinuousClock.now + .seconds(10)
                while ContinuousClock.now < deadline {
                    if await Task.detached(operation: answers).value { return true }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                return false
            }

            /// A plist under the agent's label in ~/Library/LaunchAgents is a
            /// second definition of the same job, loaded at every login and
            /// holding the label the bundled agent needs (awake's early
            /// installs left one): booted out and moved to the Trash first.
            private func removeStrayDefinition() {
                guard case .agent = kind, let label else { return }
                let stray = FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: "Library/LaunchAgents/\(label).plist")
                guard FileManager.default.fileExists(atPath: stray.path) else { return }
                _ = AppInstallation.launchctl(["bootout", "gui/\(getuid())", stray.path])
                do {
                    try FileManager.default.trashItem(at: stray, resultingItemURL: nil)
                    installLog.warn("a stray definition went to the Trash", ["path": stray.path])
                } catch {
                    installLog.error("stray definition stays", ["path": stray.path, "err": error])
                }
            }

            /// Membership of the `admin` group, the one that can approve a
            /// LaunchDaemon. The group and the current user always exist on
            /// macOS; a lookup that fails is a broken world, not a standard
            /// user.
            public static var userIsAdmin: Bool {
                guard let admin = getgrnam("admin") else { preconditionFailure("no admin group") }
                guard let user = getpwuid(getuid()) else {
                    preconditionFailure("no passwd entry for uid")
                }
                var count: Int32 = 64
                var groups = [gid_t](repeating: 0, count: Int(count))
                let rc = groups.withUnsafeMutableBufferPointer { buffer in
                    buffer.baseAddress!.withMemoryRebound(to: Int32.self, capacity: Int(count)) {
                        getgrouplist(user.pointee.pw_name, Int32(user.pointee.pw_gid), $0, &count)
                    }
                }
                precondition(rc >= 0, "getgrouplist overflowed \(groups.count) groups")
                return groups.prefix(Int(count)).contains(admin.pointee.gr_gid)
            }
        }

        /// What `/bin/launchctl` prints for these arguments ("" when it fails).
        /// A label's launchd address: the system domain for a daemon, the
        /// person's GUI domain otherwise.
        static func launchdTarget(label: String, daemon: Bool) -> String {
            daemon ? "system/\(label)" : "gui/\(getuid())/\(label)"
        }

        /// The image launchd's record of a job names (its `Executable`, as
        /// SMAppService resolved it when registering), or nil when launchd
        /// holds no such job.
        static func registeredImage(_ target: String) -> String? {
            launchctlOutput(["print", target]).split(separator: "\n").lazy
                .compactMap { line -> String? in
                    guard let range = line.range(of: "\"Executable\" => \"") else { return nil }
                    return line[range.upperBound...].split(separator: "\"").first.map(String.init)
                }.first
        }

        /// The executable a process runs, as the kernel names it now (a
        /// rename shows; a copy in the Trash shows as the Trash). Any
        /// process's, root's included, readable without root.
        static func image(of pid: pid_t) -> String? {
            var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { return nil }
            return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
        }

        /// The process launchd runs for a job right now, or nil.
        static func launchdPID(_ target: String) -> pid_t? {
            let output = launchctlOutput(["print", target])
            guard output.contains("\tstate = running") else { return nil }
            return output.split(separator: "\n").lazy
                .compactMap { line -> pid_t? in
                    let field = line.trimmingCharacters(in: .whitespaces)
                    guard field.hasPrefix("pid = ") else { return nil }
                    return pid_t(field.dropFirst("pid = ".count))
                }.first
        }

        static func launchctlOutput(_ arguments: [String]) -> String {
            run("/bin/launchctl", arguments).output
        }

        /// Opens `app` as a new instance in the background, no window
        /// brought forward (`open -n -g -j`), with `arguments` after `--args`;
        /// open's exit status once the app is launched.
        static func openHeadless(_ app: URL, _ arguments: [String]) -> Int32 {
            run("/usr/bin/open", ["-n", "-g", "-j", app.path, "--args"] + arguments).status
        }

        /// `/bin/launchctl` with these arguments; its exit status.
        @discardableResult
        static func launchctl(_ arguments: [String]) -> Int32 {
            run("/bin/launchctl", arguments).status
        }

        /// A system tool (launchctl, open) through `posix_spawn` + `waitpid`, never
        /// Foundation's `Process`: `waitUntilExit` spins the calling thread's
        /// run loop, and a job's state is read while SwiftUI draws (a grant's
        /// standing), where a turn of the run loop re-enters a layout half
        /// done (a page dot row once drew a phantom slot). This blocks for
        /// launchctl's few milliseconds and runs nothing else meanwhile.
        private static func run(_ path: String, _ arguments: [String]) -> (
            status: Int32, output: String
        ) {
            var actions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&actions)
            defer { posix_spawn_file_actions_destroy(&actions) }
            var pipe: [Int32] = [0, 0]
            guard Darwin.pipe(&pipe) == 0 else { return (-1, "") }
            posix_spawn_file_actions_adddup2(&actions, pipe[1], STDOUT_FILENO)
            posix_spawn_file_actions_addclose(&actions, pipe[0])
            posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
            let words: [String] = [path] + arguments
            let argv: [UnsafeMutablePointer<CChar>?] = words.map { strdup($0) } + [nil]
            defer { argv.forEach { free($0) } }
            var pid: pid_t = 0
            let spawned = posix_spawn(&pid, path, &actions, nil, argv, environ)
            close(pipe[1])
            defer { close(pipe[0]) }
            guard spawned == 0 else {
                installLog.error(
                    "did not start", ["tool": path, "args": arguments, "errno": spawned])
                return (-1, "")
            }
            let output = FileHandle(fileDescriptor: pipe[0]).readDataToEndOfFile()
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            let exit = (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1
            return (exit, String(decoding: output, as: UTF8.self))
        }
    }
#endif
