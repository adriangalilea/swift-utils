#if os(macOS)
    import AppInstallations
    import Log
    import ServiceManagement
    import Synchronization

    private let grantLog = log.scope("grant")

    /// A background service's grant: the person's side of a job the app runs
    /// beside itself (`AppInstallation.Job`). The job owns the machinery
    /// (registering, approval, its probe, the place the bundle stands);
    /// this renders its state and asks the one way each state is fixed.
    enum JobGrant {
        static func standing(_ job: AppInstallation.Job) -> PermissionGrant.Standing {
            if let failure = failures.withLock({ $0[job.name] }) {
                return .broken("Try Again", note: failure)
            }
            let state = job.state
            record(job, state)
            switch state {
            case .running:
                return .good
            case .off:
                return .askable("Turn On")
            case .awaitingApproval(let needsAdmin):
                return .broken(
                    "Open Login Items",
                    note: needsAdmin
                        ? "An admin must allow it in Login Items."
                        : "Waiting for your OK in Login Items.")
            case .silent:
                return .broken("Restart", note: "Installed, but not answering.")
            case .misplaced:
                return .broken(
                    AppInstallation.installedCopy != nil
                        ? "Open in Applications" : "Move to Applications",
                    note: "Only works from the Applications folder.")
            case .bare:
                return .unknown(note: "Not part of this build.")
            }
        }

        /// The state's one fix: move the app home, open Login Items, or
        /// install (which registers, waits for the OK and for an answer).
        @MainActor static func ask(_ job: AppInstallation.Job) async {
            failures.withLock { $0[job.name] = nil }
            switch job.state {
            case .running, .bare:
                return
            case .misplaced:
                do { try await AppInstallation.moveHome() } catch { fail(job, "\(error)") }
            case .awaitingApproval:
                grantLog.info("opened Login Items", ["grant": job.name])
                SMAppService.openSystemSettingsLoginItems()
            case .off, .silent:
                do { try await job.install() } catch { fail(job, "\(error)") }
            }
        }

        private static func fail(_ job: AppInstallation.Job, _ why: String) {
            grantLog.warn("could not turn on", ["grant": job.name, "why": why])
            failures.withLock { $0[job.name] = why }
        }

        /// The last failed ask per job, shown until the next ask.
        private static let failures = Mutex<[String: String]>([:])

        /// The last state logged per job: logged the first time and at each
        /// change, like the Privacy hub's readings, so `grant status` shows it.
        private static let readings = Mutex<[String: String]>([:])

        private static func record(_ job: AppInstallation.Job, _ state: AppInstallation.Job.State) {
            let words = job.words
            let changed = readings.withLock { readings in
                guard readings[job.name] != words else { return false }
                readings[job.name] = words
                return true
            }
            guard changed else { return }
            grantLog.info("reads \(state == .running ? "allowed" : words)", ["grant": job.name])
        }
    }
#endif
