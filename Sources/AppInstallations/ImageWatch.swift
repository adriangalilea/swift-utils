#if os(macOS)
    import Foundation
    import Security

    extension AppInstallation {
        /// This process keeping the app's whole life on this Mac, the same in
        /// the app and in its jobs, because a bundle deleted, moved or
        /// upgraded under a running process announces nothing and runs no hook
        /// (a Trash drag, a cask's sandboxed steps, Sparkle replacing the
        /// bundle). At the start, in the app: the jobs it was asked to turn
        /// on and the ones whose record went stale are (re)registered for
        /// this copy, and its command-line links are pointed here. Then it
        /// watches its executable:
        ///
        /// - **Gone** `goneAfter` ticks in a row (one absent tick is an
        ///   upgrade swapping bundles). With a copy of the app elsewhere it
        ///   MOVED: nothing is forgotten; a job leaves launchd (its record
        ///   names the old path, which launchd would retry forever) and the
        ///   moved copy registers it again when it opens; the app reopens
        ///   from the moved copy. With no copy anywhere it was DELETED: the
        ///   app's state goes to the Trash (`forget`) and the process leaves.
        ///   Whichever it was, `beforeLeaving` runs first (hand back what
        ///   the process holds: chilld's fans to Apple). A job leaves launchd only when launchd's process
        ///   for its label is this one: a newer copy may already have
        ///   registered the label.
        /// - **Replaced** (another file at the path) and whole: the new image
        ///   runs. Whole means signed as this one is (same designated
        ///   requirement): an installer still writing file by file leaves an
        ///   image launchd refuses, and after a few refusals it drops the job
        ///   for good. A job exits and launchd restarts it into the new image,
        ///   which needs `KeepAlive` in its plist (without it the job simply
        ///   stops); an app reopens into it.
        ///
        /// Keep it for the life of the process: `ImageWatch.start(...)`.
        public final class ImageWatch: @unchecked Sendable {
            private let path: String
            private let inode: ino_t
            /// The bundle's job this process runs as (nil: the app), read at
            /// the start while the bundle can still vouch for it.
            private let job: String?
            /// The plist declaring that job, its name in a hand-over.
            private let jobPlist: String?
            /// Who the app is and where it stood, read at the start: once the
            /// bundle is gone nothing can be read from it.
            private let bundleID: String
            private let bundle: URL
            private let keeps: [URL]
            private let links: [Link]
            private let goneAfter: Int
            private let beforeLeaving: @Sendable () -> Void
            private var gone = 0
            private var timer: DispatchSourceTimer?

            /// `jobs`: the app's own job declarations, whose probes are the
            /// witnesses when the launch (re)registers them. `keeps`: where
            /// the app keeps state beyond the standard places by bundle id
            /// (`~/Library/Logs/steno`, a dotfolder), moved to the Trash with
            /// them on delete; a daemon's are exact files it created.
            /// `links`: its command lines on PATH. `every`: how often it looks.
            /// `goneAfter`: how many looks in a row the executable must be
            /// missing before it is gone. `beforeLeaving`: what the process
            /// hands back before it stops, whatever the reason the watch found
            /// (deleted, moved, replaced): chilld's fans to Apple. It runs
            /// before any cleanup or hand-over, since a hand-over's fresh
            /// registration stops this process.
            public static func start(
                jobs: [Job] = [], keeps: [URL] = [], links: [Link] = [],
                every: Duration = .seconds(1), goneAfter: Int = 15,
                beforeLeaving: @escaping @Sendable () -> Void = {}
            ) -> ImageWatch {
                guard let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
                    preconditionFailure("a process with no executable URL")
                }
                guard let bundle = AppInstallation.bundle,
                    let bundleID = Bundle(url: bundle)?.bundleIdentifier
                else {
                    preconditionFailure(
                        "ImageWatch watches an installed app; this is a bare build: \(path)")
                }
                var info = stat()
                precondition(stat(path, &info) == 0, "the running executable is missing: \(path)")
                let watch = ImageWatch(
                    path: path, inode: info.st_ino, job: AppInstallation.ownJob,
                    bundleID: bundleID, bundle: bundle, keeps: keeps, links: links,
                    goneAfter: goneAfter, beforeLeaving: beforeLeaving)
                installLog.info("watching the image", ["path": path, "as": watch.job ?? "the app"])
                if watch.job == nil {
                    let arguments = CommandLine.arguments
                    if let flag = arguments.firstIndex(of: Job.forgetArgument),
                        arguments.indices.contains(flag + 1)
                    {
                        // Run from the Trash by the root job that saw the app
                        // deleted: the person's side goes, links into the
                        // path the app was deleted from included, before
                        // anything here could re-point them at the Trash.
                        let deleted = URL(filePath: arguments[flag + 1])
                        installLog.warn(
                            "forgetting the deleted app for this person",
                            ["was": deleted.path, "copy": bundle.path])
                        AppInstallation.forget(
                            bundleID: bundleID, bundle: deleted, keeps: keeps, links: links)
                        exit(0)
                    }
                    // A new copy of the app is where a job's record and a
                    // link into the bundle go stale.
                    AppInstallation.repoint(links, to: bundle, bundleID: bundleID)
                    if arguments.contains(Job.staleArgument) {
                        // Opened by a moved job's old process to register it
                        // here: done before any window, then gone.
                        let done = DispatchSemaphore(value: 0)
                        Task.detached {
                            await Job.settle(in: bundle, own: jobs, arguments: arguments)
                            done.signal()
                        }
                        done.wait()
                        installLog.info("registered for this copy; exiting", ["path": bundle.path])
                        exit(0)
                    }
                    Task.detached { await Job.settle(in: bundle, own: jobs, arguments: arguments) }
                }
                watch.begin(every: every)
                return watch
            }

            private init(
                path: String, inode: ino_t, job: (label: String, plist: String)?, bundleID: String,
                bundle: URL,
                keeps: [URL], links: [Link], goneAfter: Int,
                beforeLeaving: @escaping @Sendable () -> Void
            ) {
                self.path = path
                self.inode = inode
                self.job = job?.label
                self.jobPlist = job?.plist
                self.bundleID = bundleID
                self.bundle = bundle
                self.keeps = keeps
                self.links = links
                self.goneAfter = goneAfter
                self.beforeLeaving = beforeLeaving
            }

            private func begin(every: Duration) {
                let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                let interval =
                    Double(every.components.seconds)
                    + Double(every.components.attoseconds) / 1e18
                timer.schedule(
                    deadline: .now() + interval, repeating: interval, leeway: .milliseconds(200))
                timer.setEventHandler { [self] in tick() }
                timer.resume()
                self.timer = timer
            }

            private func tick() {
                var info = stat()
                guard stat(path, &info) == 0 else {
                    gone += 1
                    installLog.info(
                        "executable missing", ["path": path, "tick": gone, "of": goneAfter])
                    guard gone >= goneAfter else { return }
                    timer?.cancel()
                    if let moved = AppInstallation.movedCopy(
                        of: bundleID, named: bundle.lastPathComponent, besides: bundle,
                        executable: inode)
                    {
                        installLog.info(
                            "the app moved: leaving, nothing forgotten",
                            ["from": bundle.path, "to": moved.path])
                        beforeLeaving()
                        AppInstallation.leave(job: job, reopening: moved, handoff: jobPlist)
                        return
                    }
                    installLog.warn(
                        "the app was deleted: cleaning up and leaving", ["path": bundle.path])
                    beforeLeaving()
                    let forget: @Sendable () -> Void = { [bundleID, bundle, keeps, links] in
                        AppInstallation.forget(
                            bundleID: bundleID, bundle: bundle, keeps: keeps, links: links)
                    }
                    if job != nil {
                        forget()
                        if getuid() == 0 { AppInstallation.forgetForPerson(deleted: bundle) }
                    } else {
                        // The app saves its state as it quits (its terminate,
                        // AppKit's window frames): forgetting first, the quit
                        // would write part of it back. So it quits, and the
                        // state goes to the Trash at the process's exit,
                        // after every save.
                        AppInstallation.atExit(forget)
                    }
                    AppInstallation.leave(job: job, reopening: nil)
                    return
                }
                gone = 0
                guard info.st_ino != inode else { return }
                guard Self.wholeAsSelf(path) else {
                    installLog.info("a new image, not whole yet", ["path": path])
                    return
                }
                timer?.cancel()
                installLog.info("a new image is in place: running it", ["path": path])
                // Before the hand-over: the new copy's fresh registration
                // stops this process, maybe mid-wait.
                beforeLeaving()
                if let job {
                    // launchd would restart the bundle it registered (the old
                    // one, now in the Trash): the copy at this path takes the
                    // job instead. A daemon exits; the app's launch rebinds it.
                    if let jobPlist {
                        AppInstallation.handOver(
                            AppInstallation.launchdTarget(label: job, daemon: getuid() == 0),
                            jobPlist,
                            to: bundle)
                    }
                    exit(0)
                }
                AppInstallation.reopen("an upgrade landed")
            }

            /// The image at `path` is complete and signed as this process is:
            /// its designated requirement holds for the new code.
            static func wholeAsSelf(_ path: String) -> Bool {
                var me: SecCode?
                var mine: SecStaticCode?
                var requirement: SecRequirement?
                guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
                    SecCodeCopyStaticCode(me, [], &mine) == errSecSuccess, let mine,
                    SecCodeCopyDesignatedRequirement(mine, [], &requirement) == errSecSuccess
                else { return false }
                var code: SecStaticCode?
                guard
                    SecStaticCodeCreateWithPath(URL(filePath: path) as CFURL, [], &code)
                        == errSecSuccess,
                    let code
                else { return false }
                return SecStaticCodeCheckValidity(
                    code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
                    == errSecSuccess
            }
        }

        /// The label of the bundle's own job this process runs as, or nil for
        /// the app. launchd names every process it starts, an app opened from
        /// Finder included (LaunchServices gives it an `application.…`
        /// label), so the name alone says nothing: it counts only when one of
        /// the bundle's job plists declares it. Read while the bundle exists:
        /// once it is deleted, the plists that vouch for the label are gone.
        public static var ownJobLabel: String? { ownJob?.label }

        /// The job this process runs as: its label and the plist declaring
        /// it (the job's hand-off name), or nil for the app.
        static var ownJob: (label: String, plist: String)? {
            guard let label = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"],
                !label.isEmpty, label != "0", let bundle
            else { return nil }
            return ["Contents/Library/LaunchAgents", "Contents/Library/LaunchDaemons"]
                .lazy.flatMap { folder in
                    let dir = bundle.appending(path: folder)
                    let names =
                        (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
                    return names.compactMap { plist -> (label: String, plist: String)? in
                        NSDictionary(contentsOf: dir.appending(path: plist))?["Label"] as? String
                            == label ? (label, plist) : nil
                    }
                }.first
        }

        /// This job's registration is stale (its app moved, or was replaced
        /// by a new bundle: launchd would respawn the old one, from the Trash
        /// or a vanished path), and this process is the witness. The copy
        /// that is THE app now, opened headless, registers it afresh, which
        /// stops this process too; returns if that did not happen within 20
        /// seconds. A root daemon cannot open apps in the person's session:
        /// it returns at once, and the app registers it at its next launch.
        static func handOver(_ target: String, _ handoff: String, to app: URL) {
            guard getuid() != 0 else { return }
            installLog.info(
                "asking the app's current copy to take this job", ["job": target, "to": app.path])
            guard open(app, arguments: [Job.staleArgument, handoff], background: true) == 0 else {
                installLog.warn(
                    "could not open the app's current copy", ["job": target, "app": app.path])
                return
            }
            Thread.sleep(forTimeInterval: 20)
            installLog.warn("still running after the hand-over", ["job": target])
        }

        /// A root job removes only what root created; the person's side of a
        /// deleted app (its state, preferences, links) is the app's to
        /// forget, and any process of it in the person's session does so as
        /// it leaves. When none is alive (the app quit before the delete,
        /// the daemon alone left), the deleted copy, still in the Trash, is
        /// run as the person at the console with `Job.forgetArgument`: its
        /// own declarations know what to forget. With the Trash emptied or
        /// nobody at the console, that side stays.
        static func forgetForPerson(deleted bundle: URL) {
            guard let image = image(of: getpid()), let copy = app(around: image),
                let executable = Bundle(url: copy)?.executableURL?.path,
                FileManager.default.isExecutableFile(atPath: executable)
            else {
                installLog.warn(
                    "the deleted copy is gone: the person's side stays", ["was": bundle.path])
                return
            }
            if let alive = processes(inside: copy).first {
                installLog.info("a process of the app forgets the person's side", ["pid": alive])
                return
            }
            var console = stat()
            guard stat("/dev/console", &console) == 0, console.st_uid != 0,
                let person = getpwuid(console.st_uid)
            else {
                installLog.warn(
                    "nobody at the console: the person's side stays", ["was": bundle.path])
                return
            }
            let name = String(cString: person.pointee.pw_name)
            let status = run(
                "/bin/launchctl",
                [
                    "asuser", String(console.st_uid), "/usr/bin/sudo", "-H", "-u", name,
                    executable, Job.forgetArgument, bundle.path,
                ]
            ).status
            installLog.info(
                "the deleted copy ran for the person", ["person": name, "status": status])
        }

        /// The process leaves for good. A job boots its label out of launchd
        /// (its domain by who runs it: root's daemon is system's), launchd
        /// killing it inside the call, but only while launchd's process for
        /// the label is this one: when a newer copy has registered the label
        /// since, booting it out would stop that copy's job, so this one just
        /// exits. The app quits, or reopens from `reopening` (a moved copy).
        static func leave(job: String?, reopening moved: URL?, handoff: String? = nil) {
            if let label = job {
                let target = launchdTarget(label: label, daemon: getuid() == 0)
                if let moved, let handoff { handOver(target, handoff, to: moved) }
                if launchdPID(target) == getpid() {
                    installLog.warn("leaving launchd", ["job": target])
                    launchctl(["bootout", target])
                } else {
                    installLog.info(
                        "launchd's job is another copy's now: exiting only", ["job": target])
                }
                exit(0)
            }
            if let moved, open(moved) != 0 {
                installLog.error("could not reopen the moved app", ["at": moved.path])
            }
            quit()
        }
    }
#endif
