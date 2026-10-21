#if os(macOS)
    import AppKit
    import Log

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
        /// Where this app's bundle stands.
        public enum Home: Equatable, Sendable {
            /// In /Applications: the one place a registration may be bound to.
            case applications
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
                case .applications: "Applications"
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
        /// (a command line symlinked into ~/.local/bin is the same app).
        public static var bundle: URL? {
            guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
                return nil
            }
            let bundle = executable.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
            return bundle.pathExtension == "app" ? bundle : nil
        }

        public static var home: Home {
            guard let bundle else { return .noBundle }
            if bundle.deletingLastPathComponent().path == "/Applications" { return .applications }
            if bundle.path.hasPrefix("/Volumes/") { return .elsewhere(bundle, .diskImage) }
            if bundle.path.contains("/AppTranslocation/") {
                return .elsewhere(bundle, .translocated)
            }
            return .elsewhere(bundle, .folder)
        }

        /// The app where it belongs: /Applications/<its name>.
        public static var homeURL: URL? {
            bundle.map { URL(filePath: "/Applications").appending(path: $0.lastPathComponent) }
        }

        /// An install already in /Applications, which is THE app.
        public static var installedCopyExists: Bool {
            homeURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
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
        /// install already in /Applications is THE app and is opened;
        /// otherwise this bundle is copied there (a copy: a disk image is
        /// read-only and a translocated bundle's origin is hidden from it),
        /// that copy is opened, and this process quits. A new instance,
        /// since it shares this process's bundle id.
        @MainActor public static func moveHome() async throws {
            guard let bundle, let homeURL else { throw MoveError.noBundle }
            if !installedCopyExists {
                do {
                    try FileManager.default.copyItem(at: bundle, to: homeURL)
                    installLog.info("copied into Applications", ["from": bundle.path])
                } catch {
                    throw MoveError.copy(error.localizedDescription)
                }
            }
            let open = NSWorkspace.OpenConfiguration()
            open.createsNewApplicationInstance = true
            do {
                _ = try await NSWorkspace.shared.openApplication(at: homeURL, configuration: open)
            } catch {
                throw MoveError.open(error.localizedDescription)
            }
            installLog.info("opened the app in Applications; leaving", ["from": bundle.path])
            NSApp?.terminate(nil)
        }

        /// Opens a new instance of this bundle, then quits this one: an
        /// upgrade landed on disk, or a change that applies on reopen.
        @MainActor public static func reopen(_ why: String) {
            let open = NSWorkspace.OpenConfiguration()
            open.createsNewApplicationInstance = true
            installLog.info("reopening", ["why": why])
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: open) {
                _, error in
                if let error {
                    installLog.error("reopen failed", ["why": why, "err": error])
                    return
                }
                Task { @MainActor in NSApp?.terminate(nil) }
            }
        }
    }
#endif
