#if os(macOS)
    import CoreServices
    import Foundation
    import Synchronization

    // The few things an app does to itself and to other copies of itself,
    // through the system's own tools rather than AppKit, so every process of
    // an app links this module: the app, and the agents and root daemons that
    // deliberately carry no AppKit (chilld, authzd).
    extension AppInstallation {
        /// Opens `app` as a new instance (`open -n`), with `arguments` after
        /// `--args`; `background` keeps it from coming forward and from
        /// showing a window (`-g -j`: a headless hand-over). open's status.
        @discardableResult
        static func open(_ app: URL, arguments: [String] = [], background: Bool = false) -> Int32 {
            run(
                "/usr/bin/open",
                ["-n"] + (background ? ["-g", "-j"] : []) + [app.path]
                    + (arguments.isEmpty ? [] : ["--args"] + arguments)
            ).status
        }

        /// Brings `app`, already running, forward (`open` without `-n`).
        static func activate(_ app: URL) {
            run("/usr/bin/open", [app.path])
        }

        /// A process runs this app's executable right now: every process's
        /// image (`proc_pidpath`) against the bundle's executable.
        static func isRunning(_ app: URL) -> Bool {
            guard let executable = Bundle(url: app)?.executableURL?.resolvingSymlinksInPath().path
            else { return false }
            return !otherProcesses(where: { $0 == executable }).isEmpty
        }

        /// Every other process whose image is inside `bundle` (the app, its
        /// agents, its helpers), wherever the bundle is now.
        static func processes(inside bundle: URL) -> [pid_t] {
            let prefix = bundle.standardizedFileURL.path + "/"
            return otherProcesses(where: { $0.hasPrefix(prefix) })
        }

        private static func otherProcesses(where matches: (String) -> Bool) -> [pid_t] {
            let count = proc_listallpids(nil, 0)
            guard count > 0 else { return [] }
            var pids = [pid_t](repeating: 0, count: Int(count) + 32)
            let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
            return pids.prefix(Int(max(filled, 0))).filter { pid in
                pid > 0 && pid != getpid() && image(of: pid).map(matches) == true
            }
        }

        /// Every copy of the app Spotlight knows by its bundle id (where a
        /// rename took it, a download, a build folder). Spotlight is the one
        /// index of bundles by id outside AppKit; a disk it does not index
        /// lends nothing, and the Applications folders are checked on their
        /// own.
        static func indexedCopies(of bundleID: String) -> [URL] {
            run("/usr/bin/mdfind", ["kMDItemCFBundleIdentifier == '\(bundleID)'"]).output
                .split(separator: "\n").map { URL(filePath: String($0)) }
        }

        /// Runs `work` as the process exits, after the app's own terminate
        /// (`exit` runs it, the quit included). Once per process.
        static func atExit(_ work: @escaping @Sendable () -> Void) {
            exitWork.withLock { $0 = work }
            atexit { AppInstallation.exitWork.withLock { $0 }?() }
        }

        private static let exitWork = Mutex<(@Sendable () -> Void)?>(nil)

        /// The app quits itself as the Dock's Quit does: a Quit Apple Event
        /// to its own process, which AppKit answers with a normal terminate
        /// (its state saved, `applicationWillTerminate` run). A process with
        /// no event loop to answer it is the bundle's leftover: it exits.
        public static func quit() {
            installLog.info("quitting", ["pid": getpid()])
            // Sent from the main thread: an event to its own process is
            // handled on the sender's thread, and AppKit refuses to terminate
            // from any other ("App termination on a secondary thread is not
            // currently supported", measured from the watch's queue).
            DispatchQueue.main.async {
                let event = NSAppleEventDescriptor(
                    eventClass: AEEventClass(kCoreEventClass),
                    eventID: AEEventID(kAEQuitApplication),
                    targetDescriptor: NSAppleEventDescriptor(processIdentifier: getpid()),
                    returnID: AEReturnID(kAutoGenerateReturnID),
                    transactionID: AETransactionID(kAnyTransactionID))
                if let raw = event.aeDesc {
                    AESendMessage(raw, nil, AESendMode(kAENoReply), kAEDefaultTimeout)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                installLog.warn("nothing answered the quit: exiting", ["pid": getpid()])
                exit(0)
            }
        }
    }
#endif
