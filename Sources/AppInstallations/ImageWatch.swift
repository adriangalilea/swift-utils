#if os(macOS)
    import AppKit
    import Security

    extension AppInstallation {
        /// This process watching its own executable, the same in the app and
        /// in its jobs, because a bundle deleted or upgraded under a running
        /// process announces nothing and runs no hook (a Trash drag, a cask's
        /// sandboxed steps, Sparkle replacing the bundle):
        ///
        /// - **Gone** `goneAfter` ticks in a row (one absent tick is an
        ///   upgrade swapping bundles): `onGone` runs (hand back what the
        ///   process holds, its state to the Trash), then the process leaves:
        ///   a launchd job boots itself out of launchd (a deleted app cannot
        ///   unregister it, and KeepAlive would retry the missing binary
        ///   forever), an app quits.
        /// - **Replaced** (another file at the path) and whole: the new image
        ///   runs. Whole means signed as this one is (same designated
        ///   requirement): an installer still writing file by file leaves an
        ///   image launchd refuses, and after a few refusals it drops the job
        ///   for good. A launchd job exits and launchd restarts it into the new
        ///   image, which needs `KeepAlive` in its plist (without it the job
        ///   simply stops); an app reopens into it.
        ///
        /// Keep it for the life of the process: `ImageWatch.start(...)`.
        public final class ImageWatch: @unchecked Sendable {
            private let path: String
            private let inode: ino_t
            /// The bundle's job this process runs as (nil: the app), read at
            /// the start while the bundle can still vouch for it.
            private let job: String?
            private let goneAfter: Int
            private let onGone: @Sendable () -> Void
            private var gone = 0
            private var timer: DispatchSourceTimer?

            /// `every`: how often it looks. `goneAfter`: how many looks in a
            /// row the executable must be missing before it is gone.
            public static func start(
                every: Duration = .seconds(1), goneAfter: Int = 15,
                onGone: @escaping @Sendable () -> Void
            ) -> ImageWatch {
                guard let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
                    preconditionFailure("a process with no executable URL")
                }
                var info = stat()
                precondition(stat(path, &info) == 0, "the running executable is missing: \(path)")
                let watch = ImageWatch(
                    path: path, inode: info.st_ino, job: AppInstallation.ownJobLabel,
                    goneAfter: goneAfter, onGone: onGone)
                installLog.info("watching the image", ["path": path, "as": watch.job ?? "the app"])
                // A new copy of the app is where a job's record goes stale.
                if watch.job == nil { Job.reattachDeclared() }
                watch.begin(every: every)
                return watch
            }

            private init(
                path: String, inode: ino_t, job: String?, goneAfter: Int,
                onGone: @escaping @Sendable () -> Void
            ) {
                self.path = path
                self.inode = inode
                self.job = job
                self.goneAfter = goneAfter
                self.onGone = onGone
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
                    installLog.warn("the app is gone: cleaning up and leaving", ["path": path])
                    onGone()
                    AppInstallation.leave(job: job)
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
                if job != nil {
                    exit(0)  // KeepAlive restarts the job into the new image.
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { AppInstallation.reopen("an upgrade landed") }
                }
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
        public static var ownJobLabel: String? {
            guard let label = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"],
                !label.isEmpty, label != "0", let bundle
            else { return nil }
            let declared = ["Contents/Library/LaunchAgents", "Contents/Library/LaunchDaemons"]
                .flatMap { folder in
                    let dir = bundle.appending(path: folder)
                    let names =
                        (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
                    return names.compactMap {
                        NSDictionary(contentsOf: dir.appending(path: $0))?["Label"] as? String
                    }
                }
            return declared.contains(label) ? label : nil
        }

        /// The process leaves for good: a job boots itself out (its domain by
        /// who runs it: root's daemon is system's), launchd killing it inside
        /// the call; the app quits.
        static func leave(job: String?) {
            if let label = job {
                let domain = getuid() == 0 ? "system/\(label)" : "gui/\(getuid())/\(label)"
                installLog.warn("leaving launchd", ["job": domain])
                launchctl(["bootout", domain])
                exit(0)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { NSApp?.terminate(nil) } }
        }
    }
#endif
