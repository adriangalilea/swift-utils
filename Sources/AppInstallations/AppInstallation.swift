#if os(macOS)
    import Foundation
    import Log
    import Security

    let installLog = log.scope("install")

    /// An app's whole life on the Mac, the app's own job (the studio rule:
    /// install, open, one press, the OS's one approval, working; delete it,
    /// gone): where its bundle lives and moving it home (`home`,
    /// `moveHome`), the processes it runs beside itself (`Job`: a launch
    /// agent, a root daemon, the app as a login item), an upgrade landing on
    /// disk and the bundle deleted (`ImageWatch`, in the app and in its jobs).
    ///
    /// Every piece is distilled from apps that shipped it (chill's daemon,
    /// awake's agent), so each rule here is a failure someone met:
    ///
    /// - `SMAppService.Status.notFound` alone means three things, so the
    ///   status is read against where the bundle stands (`Home`).
    /// - `.enabled` is Background Task Management's record, not launchd's: a
    ///   job can be enabled and not loaded (chill after a reinstall) or loaded
    ///   and stuck (awake after refused launches). The truth is the job
    ///   answering, a probe the app owns (`Job.answers`); silent, it is
    ///   registered again, once.
    /// - Registering right after unregistering fails (EPERM) until BTM
    ///   settles, for seconds: retried.
    /// - A bundle missing for an instant is an upgrade mid-copy, not a
    ///   deletion: gone counts only after several ticks in a row.
    /// - A deleted app cannot unregister (SMAppService resolves the plist
    ///   through the bundle): its jobs boot themselves out of launchd, and
    ///   the Login Items record stays for a reinstall to reuse.
    ///
    /// The module's one top-level name; everything else is nested here.
    public enum AppInstallation {
        /// Who an install is for, macOS Installer's own question: everyone
        /// on this Mac (/Applications) or just this account
        /// (~/Applications). Data never follows it: settings, records and
        /// caches are per account wherever the bundle lives, so an install
        /// for everyone still keeps each account's data apart.
        public enum Scope: Hashable, Sendable, CaseIterable {
            case everyone
            case me

            /// The Applications folder this scope installs into.
            public var folder: URL {
                switch self {
                case .everyone: URL(filePath: "/Applications")
                case .me:
                    FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")
                }
            }

            /// The choice, in the Installer's words.
            public var words: String {
                switch self {
                case .everyone: "For Everyone on This Mac"
                case .me: "Just for Me"
                }
            }
        }

        /// Where this app's bundle stands.
        public enum Home: Equatable, Sendable {
            /// In an Applications folder: installed, for everyone or for
            /// this account.
            case installed(Scope)
            /// Anywhere else, and where (a person knows the first two by name).
            case elsewhere(URL, Origin)
            /// Not running from an app bundle at all (a `swift build` binary).
            case noBundle

            public enum Origin: Equatable, Sendable {
                /// A mounted disk image, read-only.
                case diskImage
                /// A quarantined download macOS opened from a hidden copy.
                case translocated
                /// A folder: Downloads, a build directory.
                case folder
            }

            /// Where it stands, in a person's words.
            public var words: String {
                switch self {
                case .installed(.everyone): "Applications"
                case .installed(.me): "your own Applications folder"
                case .elsewhere(_, .diskImage): "the disk image"
                case .elsewhere(_, .translocated): "a copy macOS made of the download"
                case .elsewhere(let url, .folder):
                    url.deletingLastPathComponent().path.replacingOccurrences(
                        of: NSHomeDirectory(), with: "~")
                case .noBundle: "a bare build, outside any app"
                }
            }
        }

        /// The running app's bundle, from its executable with links resolved
        /// (a command line symlinked into ~/.local/bin is the same app). The
        /// OUTERMOST .app around the executable: a helper nested inside the
        /// app (`Contents/Library/LoginItems/authzd.app`, a tool in
        /// `Contents/Helpers`) belongs to the app that carries it, whose
        /// place, plists and identity are the ones that count.
        public static var bundle: URL? {
            Bundle.main.executableURL.flatMap { app(around: $0.resolvingSymlinksInPath().path) }
        }

        /// The outermost `.app` around `path`, or nil outside any.
        static func app(around path: String) -> URL? {
            let components = URL(filePath: path).pathComponents
            guard let outer = components.firstIndex(where: { $0.hasSuffix(".app") }) else {
                return nil
            }
            return URL(filePath: NSString.path(withComponents: Array(components[...outer])))
        }

        /// Whether this launch is this module's own (a copy opened to
        /// register, turn on or forget a job, or the new copy a stale one
        /// hands over to): the app's launch, whatever its parent. A
        /// hand-over runs the new copy's executable as a child of the old
        /// job, never through LaunchServices, so `getppid() == 1` is no
        /// sign of the app. An app that dispatches on argv (an app that is
        /// also a command line) asks this before reading a verb.
        public static func isInstallationLaunch(_ arguments: [String]) -> Bool {
            appArguments(arguments).count != arguments.count
        }

        /// The launch arguments with this module's own removed (each flag
        /// and the value after it): what the app's verb parsing reads, so a
        /// copy opened to register, turn on or forget a job is the app, never
        /// an unknown verb.
        public static func appArguments(_ arguments: [String]) -> [String] {
            let own: Set = [Job.turnOnArgument, Job.staleArgument, Job.forgetArgument]
            var kept: [String] = []
            var skip = false
            for argument in arguments {
                if skip {
                    skip = false
                } else if own.contains(argument) {
                    skip = true
                } else {
                    kept.append(argument)
                }
            }
            return kept
        }

        /// The app's name as a person sees it.
        public static var displayName: String {
            let info = (bundle.flatMap { Bundle(url: $0) } ?? Bundle.main).infoDictionary
            return info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String
                ?? ProcessInfo.processInfo.processName
        }

        /// The name in the app's signing certificate ("Apple Development:
        /// Adrian Galilea Delgado (TEAM)" → "Adrian Galilea Delgado"): what
        /// macOS shows for an app signed by a person where it names apps by
        /// developer (Login Items' Background App Activity). nil unsigned.
        public static var signerName: String? {
            var me: SecCode?
            var code: SecStaticCode?
            var info: CFDictionary?
            guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
                SecCodeCopyStaticCode(me, [], &code) == errSecSuccess, let code,
                SecCodeCopySigningInformation(
                    code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String]
                    as? [SecCertificate],
                let leaf = certificates.first,
                let summary = SecCertificateCopySubjectSummary(leaf) as String?
            else { return nil }
            let name = summary.split(separator: ":", maxSplits: 1).last.map(String.init) ?? summary
            let person = name.replacingOccurrences(
                of: #"\s*\([A-Z0-9]+\)\s*$"#, with: "", options: .regularExpression)
            return person.trimmingCharacters(in: .whitespaces)
        }

        public static var home: Home {
            guard let bundle else { return .noBundle }
            let folder = bundle.deletingLastPathComponent().standardizedFileURL.path
            if let scope = Scope.allCases.first(where: {
                $0.folder.standardizedFileURL.path == folder
            }) {
                return .installed(scope)
            }
            if bundle.path.hasPrefix("/Volumes/") { return .elsewhere(bundle, .diskImage) }
            if bundle.path.contains("/AppTranslocation/") {
                return .elsewhere(bundle, .translocated)
            }
            return .elsewhere(bundle, .folder)
        }

        /// An install of this app already in one of `scopes`' folders, which
        /// is THE app (everyone's first), and never this copy itself.
        public static func installedCopy(in scopes: [Scope] = Scope.allCases) -> URL? {
            guard let bundle else { return nil }
            return scopes.map { $0.folder.appending(path: bundle.lastPathComponent) }
                .first {
                    $0.standardizedFileURL != bundle.standardizedFileURL
                        && FileManager.default.fileExists(atPath: $0.path)
                }
        }

        public enum MoveError: Error, CustomStringConvertible {
            case noBundle
            case copy(String)
            case open(String)

            public var description: String {
                switch self {
                case .noBundle: "not running from an app bundle"
                case .copy(let why): "copying into Applications: \(why)"
                case .open(let why): "opening the app in Applications: \(why)"
                }
            }
        }

        /// Puts the app where it belongs and moves the person there: an
        /// install already in `scope`'s folder is THE app and is opened;
        /// otherwise this bundle is copied there (a copy: a disk image is
        /// read-only and a translocated bundle's origin is hidden from it),
        /// that copy is opened, and this process quits. A new instance,
        /// since it shares this process's bundle id. Which scopes to offer is
        /// the app's call; the person picks.
        /// `turningOn`: the jobs the person asked for when the move was the
        /// first step (a background service's Move button). The new copy
        /// turns them on at launch, so one press ends with the job working.
        /// Moving an install from one Applications folder to the other
        /// leaves nothing behind: the jobs this copy has on go with it
        /// (unregistered here, which stops them, then turned on there), and
        /// this copy goes to the Trash once the new one is open. A download or
        /// a build folder is never touched.
        public static func moveHome(to scope: Scope, turningOn asked: [Job] = [])
            async throws
        {
            guard let bundle else { throw MoveError.noBundle }
            let leaving: Bool = {
                if case .installed(let from) = home { return from != scope }
                return false
            }()
            let jobs =
                leaving
                ? asked
                    + Job.declared(in: bundle).filter { job in
                        job.service.status == .enabled
                            && !asked.contains { $0.handoff == job.handoff }
                    }
                : asked
            let target: URL
            if let existing = installedCopy(in: [scope]) {
                target = existing
            } else {
                target = scope.folder.appending(path: bundle.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(
                        at: scope.folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: bundle, to: target)
                    installLog.info(
                        "copied into Applications", ["from": bundle.path, "to": target.path])
                } catch {
                    throw MoveError.copy(error.localizedDescription)
                }
            }
            // THE app already running there is brought forward, never joined
            // by a second instance; launch arguments only reach a launch, so
            // the jobs asked for stay that copy's to turn on, said in the log.
            if isRunning(target) {
                activate(target)
                installLog.info(
                    "the app in Applications is already running: brought forward; leaving",
                    ["from": bundle.path, "jobs not carried": jobs.map(\.name)])
                quit()
                return
            }
            if leaving {
                // Unregistered here only now, the copy made: the new copy
                // registers them fresh, and nothing of this copy's keeps
                // running to race it.
                for job in jobs where job.kind != .loginItem {
                    do {
                        try job.uninstall()
                    } catch {
                        installLog.warn("could not hand over", ["job": job.name, "err": error])
                    }
                }
            }
            let opened = open(target, arguments: jobs.flatMap { [Job.turnOnArgument, $0.handoff] })
            guard opened == 0 else { throw MoveError.open("open exited \(opened)") }
            installLog.info(
                "opened the app in Applications; leaving",
                ["from": bundle.path, "jobs handed over": jobs.map(\.name)])
            if leaving {
                do {
                    var landed: NSURL?
                    try FileManager.default.trashItem(at: bundle, resultingItemURL: &landed)
                    installLog.info(
                        "the copy left behind moved to the Trash",
                        ["path": bundle.path, "now": landed?.path ?? "?"])
                } catch {
                    installLog.warn(
                        "could not trash the copy left behind", ["path": bundle.path, "err": error])
                }
            }
            quit()
        }

        /// Opens a new instance of this bundle, then quits this one: an
        /// upgrade landed on disk, or a change that applies on reopen.
        public static func reopen(_ why: String) {
            installLog.info("reopening", ["why": why])
            let opened = open(bundle ?? Bundle.main.bundleURL)
            guard opened == 0 else {
                installLog.error("reopen failed", ["why": why, "open": opened])
                return
            }
            quit()
        }
    }
#endif
