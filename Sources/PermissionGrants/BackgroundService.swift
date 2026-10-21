#if os(macOS)
    import AppInstallations
    import AppKit
    import Log
    import ServiceManagement
    import Synchronization

    private let grantLog = log.scope("grant")

    /// A background service's grant: the person's side of a job the app runs
    /// beside itself (`AppInstallation.Job`). The job owns the machinery
    /// (registering, approval, its probe, the place the bundle stands);
    /// this renders its state and asks the one way each state is fixed.
    enum JobGrant {
        static func standing(
            _ job: AppInstallation.Job, _ offers: [AppInstallation.Scope]
        ) -> PermissionGrant.Standing {
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
                    note: (needsAdmin ? "Needs an admin's OK. " : "Waiting for your OK. ")
                        + AppInstallation.Job.approvalSteer)
            case .silent:
                return .broken("Restart", note: "Installed, but not answering.")
            case .misplaced:
                // An install already there is opened; with a choice to make,
                // the label's ellipsis says a question comes first.
                let label =
                    AppInstallation.installedCopy(in: offers) != nil
                    ? "Open in Applications"
                    : offers.count > 1 ? "Move to Applications…" : "Move to Applications"
                return .broken(
                    label,
                    note: job.scopes == [.everyone]
                        ? "Only works installed for everyone, in Applications."
                        : "Only works from the Applications folder.")
            case .bare:
                return .unknown(note: "Not part of this build.")
            }
        }

        /// The state's one fix: move the app home, open Login Items, or
        /// install (which registers, waits for the OK and for an answer).
        @MainActor static func ask(
            _ job: AppInstallation.Job, _ offers: [AppInstallation.Scope]
        ) async {
            failures.withLock { $0[job.name] = nil }
            switch job.state {
            case .running, .bare:
                return
            case .misplaced:
                guard let scope = pick(offers) else { return }
                // The press asked for the job: the move is its first step,
                // and the new copy turns it on.
                do {
                    try await AppInstallation.moveHome(to: scope, turningOn: [job])
                } catch { fail(job, "\(error)") }
            case .awaitingApproval:
                grantLog.info("opened Login Items", ["grant": job.name])
                SMAppService.openSystemSettingsLoginItems()
            case .off, .silent:
                do { try await job.install() } catch { fail(job, "\(error)") }
            }
        }

        /// The install to move into: an existing one in an offered folder
        /// (THE app, no question), the one offered, or the person's answer
        /// to the Installer's question. nil: they cancelled.
        @MainActor private static func pick(_ offers: [AppInstallation.Scope]) -> AppInstallation
            .Scope?
        {
            if let existing = offers.first(where: {
                AppInstallation.installedCopy(in: [$0]) != nil
            }) {
                return existing
            }
            guard offers.count > 1 else { return offers[0] }
            let alert = NSAlert()
            let name =
                Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? ProcessInfo.processInfo.processName
            alert.messageText = "Install \(name) for everyone on this Mac, or just for you?"
            alert.informativeText =
                "For everyone puts it in Applications. Just for you puts it in the Applications folder in your home folder. Settings stay yours either way."
            for scope in offers { alert.addButton(withTitle: scope.words) }
            alert.addButton(withTitle: "Cancel")
            let answer =
                alert.runModal().rawValue
                - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            return offers.indices.contains(answer) ? offers[answer] : nil
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
