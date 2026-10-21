#if os(macOS)
    import AppKit

    extension AppInstallation {
        /// A command line the app puts on PATH as a link into its bundle
        /// (`~/.local/bin/mach` → `mach.app/Contents/MacOS/mach`). The link is
        /// the person's install, so it is never created here; what it points
        /// at follows the app: re-pointed when the app opens from a new copy,
        /// removed when the app is deleted.
        public struct Link: Sendable, Hashable {
            /// Where the link lives.
            public let path: URL
            /// What it points at, inside the bundle (`Contents/MacOS/mach`).
            public let inBundle: String

            public init(_ path: URL, to inBundle: String) {
                self.path = path
                self.inBundle = inBundle
            }

            /// Where the link points now, when it is a link.
            var destination: String? {
                try? FileManager.default.destinationOfSymbolicLink(atPath: path.path)
            }
        }

        /// Where the app went, if it MOVED rather than was deleted: a copy
        /// (anywhere macOS knows one, or in either Applications folder; never
        /// in a Trash or a translocated download) that is either the very
        /// files that vanished (its executable is `executable`'s inode: a
        /// rename, the Finder drag on one disk) or an install in an
        /// Applications folder (a move across disks). A leftover copy
        /// anywhere else (a download, a build folder) is neither, so deleting
        /// the install still uninstalls.
        static func movedCopy(
            of bundleID: String, named name: String, besides: URL, executable inode: ino_t
        ) -> URL? {
            let known = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
            let installs = Scope.allCases.map { $0.folder.appending(path: name) }
            let gone = besides.standardizedFileURL.path
            let installPaths = Set(installs.map(\.standardizedFileURL.path))
            var seen = Set<String>()
            return (installs + known).first { url in
                let path = url.standardizedFileURL.path
                guard path != gone, seen.insert(path).inserted,
                    !path.contains("/.Trash/"), !path.contains("/.Trashes/"),
                    !path.contains("/AppTranslocation/"),
                    let copy = Bundle(url: url), copy.bundleIdentifier == bundleID
                else { return false }
                if installPaths.contains(path) { return true }
                var info = stat()
                guard let executable = copy.executableURL?.path,
                    stat(executable, &info) == 0
                else { return false }
                return info.st_ino == inode
            }
        }

        /// The places an app keeps its state by its bundle id, the standard
        /// ones macOS and the frameworks write: what delete-is-uninstall
        /// moves to the Trash beside what the app declares. A root process
        /// has none (its home is root's): it removes only what it declares.
        static func standardState(of bundleID: String) -> [URL] {
            guard getuid() != 0 else { return [] }
            let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
            return [
                "Application Support/\(bundleID)", "Caches/\(bundleID)", "HTTPStorages/\(bundleID)",
                "WebKit/\(bundleID)", "Saved Application State/\(bundleID).savedState",
            ].map { library.appending(path: $0) }
        }

        /// Delete is the uninstall: the app's state goes to the Trash (the
        /// standard places by bundle id, then `keeps`, the app's own), its
        /// preferences with it (a copy in the Trash, the domain cleared
        /// through cfprefsd, which caches it), and the links into the deleted
        /// bundle are removed. Idempotent, since the app and each of its jobs
        /// may all run it: a place already gone is skipped. Every move is
        /// logged with its path, the undo breadcrumb. As root (a daemon), only
        /// `keeps`, by exact name: a file is removed, a directory only when
        /// empty, never recursively.
        static func forget(bundleID: String, bundle: URL, keeps: [URL], links: [Link]) {
            let fm = FileManager.default
            if getuid() == 0 {
                for url in keeps {
                    var isDirectory: ObjCBool = false
                    guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                        continue
                    }
                    if isDirectory.boolValue,
                        !((try? fm.contentsOfDirectory(atPath: url.path))?.isEmpty ?? false)
                    {
                        installLog.warn("left in place: not empty", ["path": url.path])
                        continue
                    }
                    do {
                        try fm.removeItem(at: url)
                        installLog.info("removed", ["path": url.path])
                    } catch {
                        installLog.warn("could not remove", ["path": url.path, "err": error])
                    }
                }
                return
            }
            for url in standardState(of: bundleID) + keeps where fm.fileExists(atPath: url.path) {
                trash(url)
            }
            let preferences = fm.homeDirectoryForCurrentUser
                .appending(path: "Library/Preferences/\(bundleID).plist")
            if fm.fileExists(atPath: preferences.path) {
                // A copy in the Trash only when the domain holds anything: a
                // second process cleaning up meets cfprefsd's empty file.
                let keys =
                    CFPreferencesCopyKeyList(
                        bundleID as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                    as? [String] ?? []
                if !keys.isEmpty {
                    let copy = fm.temporaryDirectory.appending(path: "\(bundleID).plist")
                    try? fm.removeItem(at: copy)
                    if (try? fm.copyItem(at: preferences, to: copy)) != nil { trash(copy) }
                }
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                CFPreferencesAppSynchronize(bundleID as CFString)
                // cfprefsd leaves the cleared domain as an empty file; with
                // its contents in the Trash and nothing of the app left to
                // write it, the file goes too.
                try? fm.removeItem(at: preferences)
                installLog.info("preferences cleared (a copy in the Trash)", ["domain": bundleID])
            }
            let inside = bundle.standardizedFileURL.path + "/"
            for link in links {
                guard let destination = link.destination,
                    URL(filePath: destination, relativeTo: link.path.deletingLastPathComponent())
                        .standardizedFileURL.path.hasPrefix(inside)
                else { continue }
                do {
                    try fm.removeItem(at: link.path)
                    installLog.info("link removed", ["path": link.path.path, "was": destination])
                } catch {
                    installLog.warn(
                        "could not remove link", ["path": link.path.path, "err": error])
                }
            }
        }

        private static func trash(_ url: URL) {
            do {
                var landed: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
                installLog.info(
                    "moved to the Trash", ["path": url.path, "now": landed?.path ?? "?"])
            } catch {
                // Another process of the app (a job beside it) got there first.
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                installLog.warn("could not move to the Trash", ["path": url.path, "err": error])
            }
        }

        /// The links point at THIS copy: a link into another copy of the app
        /// (one that moved or was replaced) or pointing at nothing is
        /// re-pointed here; one pointing anywhere else is the person's and is
        /// left alone, as is a path that holds no link.
        static func repoint(_ links: [Link], to bundle: URL, bundleID: String) {
            let fm = FileManager.default
            for link in links {
                guard let destination = link.destination else { continue }
                let target = bundle.appending(path: link.inBundle).path
                guard destination != target else { continue }
                let resolved = URL(
                    filePath: destination, relativeTo: link.path.deletingLastPathComponent()
                ).standardizedFileURL
                // Only a link shaped like this app's (into some `<x>.app` at
                // the same place inside): dangling, or into another copy.
                guard resolved.path.hasSuffix(".app/" + link.inBundle) else { continue }
                let copy = URL(filePath: String(resolved.path.dropLast(link.inBundle.count + 1)))
                let dangling = !fm.fileExists(atPath: resolved.path)
                let intoACopy = Bundle(url: copy)?.bundleIdentifier == bundleID
                guard dangling || intoACopy else { continue }
                do {
                    try fm.removeItem(at: link.path)
                    try fm.createSymbolicLink(atPath: link.path.path, withDestinationPath: target)
                    installLog.info(
                        "link re-pointed at this copy",
                        ["path": link.path.path, "was": destination, "now": target])
                } catch {
                    installLog.warn(
                        "could not re-point link", ["path": link.path.path, "err": error])
                }
            }
        }
    }
#endif
