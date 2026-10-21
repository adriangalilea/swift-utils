#if os(macOS)
    import AppKit
    import Log
    import ServiceManagement
    import Synchronization

    private let grantLog = log.scope("grant")

    /// A process the app runs beside itself through `SMAppService`: a launch
    /// agent, a root daemon, or the app as its own login item. One grant
    /// for what every app wrote again (chill's daemon, awake's and Authz's
    /// agents, mach's), judged the way chill learned to:
    ///
    /// `SMAppService.Status.notFound` alone says nothing usable. macOS
    /// answers it for a bundle with no plist for the service, for one
    /// running from the disk image or translocated (a quarantined app opened
    /// where it was downloaded), and for a service simply never registered.
    /// Each needs a different act, so the status is read against where the
    /// bundle stands (`Placement`): installable registers, misplaced moves
    /// the app into /Applications (a registration is bound to the bundle's
    /// path, and launchd boots a daemon before any home exists), bare says
    /// what is missing. Approving a DAEMON is an admin's act, and a standard
    /// account is told so instead of being sent to a switch it cannot flip.
    public struct BackgroundServiceGrant: Grant {
        public enum Kind: Hashable, Sendable {
            /// `Contents/Library/LaunchAgents/<plist>`.
            case agent(plist: String)
            /// `Contents/Library/LaunchDaemons/<plist>`, runs as root.
            case daemon(plist: String)
            /// The app itself, opened at login.
            case loginItem
        }

        public let kind: Kind
        public let symbol: String
        public let title: String
        public let why: String
        public let required: Bool

        public init(
            _ kind: Kind, title: String, why: String, symbol: String = "gearshape.2",
            required: Bool = true
        ) {
            self.kind = kind
            self.title = title
            self.why = why
            self.symbol = symbol
            self.required = required
        }

        public var service: SMAppService {
            switch kind {
            case .agent(let plist): .agent(plistName: plist)
            case .daemon(let plist): .daemon(plistName: plist)
            case .loginItem: .mainApp
            }
        }

        /// System Settings' own words for where approval happens.
        public static let approvalPath = "System Settings › General › Login Items & Extensions"

        public var standing: Standing {
            if let failure = Self.failures.withLock({ $0[kind] }) {
                return .broken("try again", note: failure)
            }
            let status = service.status
            record(status)
            switch status {
            case .enabled:
                return .good
            case .requiresApproval:
                if case .daemon = kind, !Self.userIsAdmin {
                    return .broken(
                        "open Login Items",
                        note:
                            "approving \(title) is an admin's act: ask one to allow it in \(Self.approvalPath)"
                    )
                }
                return .broken("open Login Items", note: "allow \(title) in \(Self.approvalPath)")
            case .notRegistered:
                return .askable("turn on")
            case .notFound:
                switch Placement.of(kind) {
                case .installable:
                    return .askable("turn on")
                case .misplaced(let path):
                    return .broken(
                        Placement.applicationsCopyExists
                            ? "open in Applications" : "move to Applications",
                        note:
                            "\(Self.appName) is running from \(Placement.describe(path)), and runs \(title) only from Applications"
                    )
                case .bare(let missing):
                    return .unknown(note: "this build has no \(missing): install a built app")
                }
            @unknown default:
                return .unknown(note: "\(title): registration status \(service.status.rawValue)")
            }
        }

        /// The standing's act: register, open Login Items for approval, or
        /// move the app where a registration can live.
        public func act() {
            Self.failures.withLock { $0[kind] = nil }
            switch service.status {
            case .enabled:
                return
            case .requiresApproval:
                grantLog.info("opened Login Items", ["grant": title])
                SMAppService.openSystemSettingsLoginItems()
            case .notFound:
                switch Placement.of(kind) {
                case .misplaced: MainActor.assumeIsolated { Placement.moveToApplications() }
                case .installable: register()
                case .bare: return
                }
            default:
                register()
            }
        }

        /// Off, for a service the person turns off (a login item): the
        /// reverse of `act`, idempotent.
        public func unregister() {
            guard service.status == .enabled || service.status == .requiresApproval else { return }
            do {
                try service.unregister()
                grantLog.info("unregistered", ["grant": title])
            } catch {
                grantLog.warn("unregister failed", ["grant": title, "err": error])
            }
        }

        private func register() {
            do {
                try service.register()
                grantLog.info("registered", ["grant": title, "status": service.status.rawValue])
            } catch let error as NSError where error.code == kSMErrorAlreadyRegistered {
                grantLog.info("already registered", ["grant": title])
            } catch {
                grantLog.warn("register failed", ["grant": title, "err": error])
                Self.failures.withLock { $0[kind] = error.localizedDescription }
            }
            // Approval needed: take the person to it at once, the act they
            // asked for continues there.
            if service.status == .requiresApproval {
                grantLog.info("opened Login Items", ["grant": title])
                SMAppService.openSystemSettingsLoginItems()
            }
        }

        /// A failed register, shown until the next act.
        private static let failures = Mutex<[Kind: String]>([:])

        /// The last status logged per service: a reading is logged the first
        /// time and at each change (surfaces read every second), like
        /// `Permissions`' TCC readings, so `grant status` shows it too.
        private static let readings = Mutex<[Kind: Int]>([:])

        private func record(_ status: SMAppService.Status) {
            let changed = Self.readings.withLock { readings in
                guard readings[kind] != status.rawValue else { return false }
                readings[kind] = status.rawValue
                return true
            }
            guard changed else { return }
            let word =
                switch status {
                case .enabled: "allowed"
                case .requiresApproval: "awaiting approval"
                case .notRegistered: "not asked"
                case .notFound: "not found (\(Placement.of(kind)))"
                @unknown default: "status \(status.rawValue)"
                }
            grantLog.info("reads \(word)", ["grant": title, "status": status.rawValue])
        }

        static var appName: String {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "the app"
        }

        /// Membership of the `admin` group, the one that can approve a
        /// LaunchDaemon. The group and the current user always exist on
        /// macOS; a lookup that fails is a broken world, not a standard user.
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

        /// Where this bundle stands, read from the bundle itself.
        public enum Placement: Equatable, Sendable {
            /// In /Applications with the service's plist inside: registering
            /// is the act, and its error, if any, is the truth.
            case installable
            /// Running from anywhere else.
            case misplaced(path: String)
            /// No plist for the service (a `swift build` binary or an
            /// unassembled bundle): no registration can fix it.
            case bare(missing: String)

            /// The running app's bundle, from its executable with links
            /// resolved (a CLI symlinked into ~/.local/bin is the same app).
            static var bundle: URL? {
                guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
                    return nil
                }
                let bundle = executable.deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent()
                return bundle.pathExtension == "app" ? bundle : nil
            }

            public static func of(_ kind: Kind) -> Placement {
                guard let bundle else { return .bare(missing: "app bundle") }
                let plist: String? =
                    switch kind {
                    case .agent(let name): "Contents/Library/LaunchAgents/\(name)"
                    case .daemon(let name): "Contents/Library/LaunchDaemons/\(name)"
                    case .loginItem: nil
                    }
                if let plist,
                    !FileManager.default.fileExists(atPath: bundle.appending(path: plist).path)
                {
                    return .bare(missing: plist)
                }
                guard bundle.deletingLastPathComponent().path == "/Applications" else {
                    return .misplaced(path: bundle.path)
                }
                return .installable
            }

            /// Where the app belongs, the one path a registration may be
            /// bound to.
            static var home: URL? {
                bundle.map { URL(filePath: "/Applications").appending(path: $0.lastPathComponent) }
            }

            static var applicationsCopyExists: Bool {
                home.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            }

            /// A path as a person knows it.
            static func describe(_ path: String) -> String {
                if path.hasPrefix("/Volumes/") { return "the disk image" }
                if path.contains("/AppTranslocation/") {
                    return "a copy macOS made of the download"
                }
                return path
            }

            /// Puts the app where it belongs: an install already there is
            /// THE app and is opened; otherwise this bundle is copied there
            /// (a copy, since the disk image is read-only and a translocated
            /// bundle's origin is hidden from it), opened, and this one
            /// quits.
            @MainActor static func moveToApplications() {
                guard let bundle, let home else { return }
                do {
                    if !applicationsCopyExists {
                        try FileManager.default.copyItem(at: bundle, to: home)
                        grantLog.info("copied into Applications", ["from": bundle.path])
                    }
                } catch {
                    grantLog.warn("move to Applications failed", ["err": error])
                    return
                }
                // Same bundle id as this process: without a new instance,
                // macOS would only bring this one forward.
                let open = NSWorkspace.OpenConfiguration()
                open.createsNewApplicationInstance = true
                Task {
                    do {
                        _ = try await NSWorkspace.shared.openApplication(
                            at: home, configuration: open)
                        NSApp?.terminate(nil)
                    } catch {
                        grantLog.warn(
                            "open in Applications failed", ["path": home.path, "err": error])
                    }
                }
            }
        }
    }
#endif
