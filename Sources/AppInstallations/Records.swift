#if os(macOS)
    import Foundation

    extension AppInstallation {
        /// What `onlyRecord(installed:)` did: every LaunchServices record it
        /// removed (another copy of one of the app's bundles), and each
        /// extension it saw registered.
        public struct Records: Sendable {
            public let removed: [URL]
            public let extensions: [String]
        }

        public struct RecordsError: Error, CustomStringConvertible {
            public let description: String
        }

        /// After an app is placed: the installed copy is the only LaunchServices
        /// record of every bundle it carries (the app, each `.app` inside it, a
        /// login item, each `.appex`). LaunchServices and ExtensionKit elect the
        /// newest record of an identifier, and Xcode registers every app it
        /// builds (archive intermediates, check builds, a release's working
        /// clone), as do the Trash and a mounted dmg: so a file-system module, a
        /// login item, a URL scheme can resolve to a copy that is not installed
        /// (hollow's FSKit mount, 2026-10-26). The records are read by
        /// identifier from `lsregister -dump`, never guessed from paths.
        ///
        /// The installed path itself is never unregistered, not even to register
        /// it again: an extension's enable switch follows its record, and doing
        /// so turned hollow's file-system module off until someone turned it on
        /// in System Settings. It is registered in place (`lsregister -f`), and
        /// each of its extensions added again until pluginkit lists it
        /// (pluginkit can drop one: one add was seen to take nothing for 10 s,
        /// the next landing in under a second); never listed after 20 tries is
        /// an error.
        public static func onlyRecord(
            installed app: URL, said: (String) -> Void = { _ in }
        ) throws(RecordsError) -> Records {
            let app = app.standardizedFileURL.resolvingSymlinksInPath()
            let bundles = carried(by: app)
            guard let ownID = bundles.first(where: { $0.url == app })?.identifier else {
                throw RecordsError(
                    description: "\(app.path) is not an app bundle (no CFBundleIdentifier)")
            }
            let identifiers = Set(bundles.map(\.identifier))
            var removed: [URL] = []
            for record in try dump() where identifiers.contains(record.identifier) {
                let path = record.url.standardizedFileURL.path
                guard path != app.path, !path.hasPrefix(app.path + "/") else { continue }
                if record.url.pathExtension == "appex" {
                    _ = tool(pluginkit, ["-r", record.url.path])
                }
                let (status, out) = tool(lsregister, ["-u", record.url.path])
                said(
                    "unregistered \(record.identifier) at \(record.url.path)"
                        + (status == 0 ? "" : " (lsregister said \(status): \(out))"))
                removed.append(record.url)
            }
            let (status, out) = tool(lsregister, ["-f", app.path])
            guard status == 0 else {
                throw RecordsError(
                    description: "lsregister -f \(app.path) exited \(status): \(out)")
            }
            var seen: [String] = []
            for appex in bundles where appex.url.pathExtension == "appex" {
                var listed = false
                for _ in 0..<20 {
                    _ = tool(pluginkit, ["-a", appex.url.path])
                    if tool(pluginkit, ["-m", "-i", appex.identifier]).1.contains(appex.identifier)
                    {
                        listed = true
                        break
                    }
                    sleep(1)
                }
                guard listed else {
                    throw RecordsError(
                        description:
                            "pluginkit never listed \(appex.identifier) (\(appex.url.path)) after 20 adds over 20 s"
                    )
                }
                seen.append(appex.identifier)
            }
            said(
                "\(ownID): the only record is \(app.path)\(seen.isEmpty ? "" : ", its extensions listed: \(seen.joined(separator: ", "))")"
            )
            return Records(removed: removed, extensions: seen)
        }

        /// The running app, when it is the installed copy (an Applications
        /// folder), makes itself the only record of its bundles, in the
        /// background: at every launch, so an install by any means (an
        /// installer, a kit, a Sparkle update, a drag) and the records Spotlight
        /// and Xcode keep adding between launches end with this copy the one that
        /// extensions, login items and URL schemes resolve to; the app's own
        /// login item, if on, is registered again from here
        /// (`Job.bindLoginItem`). A build run from
        /// its folder claims nothing. `ImageWatch.start` calls it; an app without
        /// one calls it at launch.
        public static func claimRecords() {
            guard case .installed = home, let bundle else { return }
            claim([bundle])
            DispatchQueue.global(qos: .utility).async { Job.bindLoginItem() }
        }

        /// `apps`, each the installed copy, made the only record of their
        /// bundles in the background: what a program that installs or serves
        /// other apps calls for them (vigil-agent for Vigil and vigild).
        public static func claim(_ apps: [URL]) {
            DispatchQueue.global(qos: .utility).async {
                for app in apps {
                    do throws(RecordsError) {
                        let records = try onlyRecord(installed: app)
                        for removed in records.removed {
                            installLog.info(
                                "record removed", ["app": app.path, "record": removed.path])
                        }
                        installLog.info(
                            "the only record",
                            [
                                "app": app.path, "removed": records.removed.count,
                                "extensions": records.extensions,
                            ])
                    } catch {
                        installLog.warn(
                            "records not claimed", ["app": app.path, "err": error.description])
                    }
                }
            }
        }

        /// Every record of the bundles `app` carries that is not in an
        /// Applications folder (nor the Trash, which LaunchServices never
        /// offers): what a build leaves behind (Xcode registers every app it
        /// builds, Finder every app it shows), each a copy of the very build a
        /// release just made, which ties with the installed copy and can win.
        /// Returns what it removed.
        @discardableResult
        public static func removeStrays(of app: URL, said: (String) -> Void = { _ in })
            throws(RecordsError) -> [URL]
        {
            let identifiers = Set(carried(by: app).map(\.identifier))
            let kept =
                Scope.allCases.map { $0.folder.standardizedFileURL.path + "/" }
                + [
                    FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash").path
                        + "/"
                ]
            var removed: [URL] = []
            for record in try dump() where identifiers.contains(record.identifier) {
                let path = record.url.standardizedFileURL.path
                guard !kept.contains(where: path.hasPrefix) else { continue }
                if record.url.pathExtension == "appex" {
                    _ = tool(pluginkit, ["-r", record.url.path])
                }
                _ = tool(lsregister, ["-u", record.url.path])
                said("unregistered \(record.identifier) at \(record.url.path)")
                removed.append(record.url)
            }
            return removed
        }

        /// Every app under `folder` (and the extensions inside each) taken out
        /// of LaunchServices: a build's output or a release artifact, never an
        /// install. Returns the apps it unregistered.
        @discardableResult
        public static func unregister(appsUnder folder: URL, said: (String) -> Void = { _ in })
            -> [URL]
        {
            var apps: [URL] = []
            let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
            while let url = walk?.nextObject() as? URL {
                if url.lastPathComponent == ".git" { walk?.skipDescendants() }
                guard url.pathExtension == "app" else { continue }
                walk?.skipDescendants()
                apps.append(url)
            }
            for app in apps {
                for appex in carried(by: app) where appex.url.pathExtension == "appex" {
                    _ = tool(pluginkit, ["-r", appex.url.path])
                }
                let (status, out) = tool(lsregister, ["-u", app.path])
                said(
                    "unregistered \(app.path)"
                        + (status == 0 ? "" : " (lsregister said \(status): \(out))"))
            }
            return apps
        }

        // MARK: Reading

        struct Carried: Equatable {
            let url: URL
            let identifier: String
        }

        /// The app and every `.app` and `.appex` inside it, each with its
        /// identifier.
        static func carried(by app: URL) -> [Carried] {
            var found: [Carried] = []
            func read(_ url: URL) {
                let plist = url.appending(path: "Contents/Info.plist")
                guard let info = NSDictionary(contentsOf: plist),
                    let identifier = info["CFBundleIdentifier"] as? String
                else { return }
                found.append(Carried(url: url, identifier: identifier))
            }
            read(app)
            let walk = FileManager.default.enumerator(
                at: app.appending(path: "Contents"), includingPropertiesForKeys: nil)
            while let url = walk?.nextObject() as? URL {
                if ["app", "appex"].contains(url.pathExtension) { read(url.standardizedFileURL) }
            }
            return found
        }

        struct Record {
            let url: URL
            let identifier: String
        }

        /// Every record LaunchServices holds, as its dump says them: a block
        /// per bundle, `path:` and `identifier:` among its lines.
        static func dump() throws(RecordsError) -> [Record] {
            let (status, out) = tool(lsregister, ["-dump"])
            guard status == 0 else {
                throw RecordsError(description: "lsregister -dump exited \(status)")
            }
            var records: [Record] = []
            var path: String?
            var identifier: String?
            func close() {
                if let path, let identifier {
                    records.append(Record(url: URL(fileURLWithPath: path), identifier: identifier))
                }
                path = nil
                identifier = nil
            }
            for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("-----") {
                    close()
                } else if line.hasPrefix("path:") {
                    // `path:  /Applications/X.app (0x1a2b)`: the record's id after it.
                    var value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if let paren = value.range(of: " (0x", options: .backwards) {
                        value = String(value[..<paren.lowerBound])
                    }
                    path = value
                } else if line.hasPrefix("identifier:"), identifier == nil {
                    identifier = line.dropFirst(11).trimmingCharacters(in: .whitespaces)
                }
            }
            close()
            return records
        }

        static let lsregister =
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        static let pluginkit = "/usr/bin/pluginkit"

        /// One of the system's tools, its status and what it said.
        static func tool(_ path: String, _ arguments: [String]) -> (Int32, String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let out = Pipe()
            process.standardOutput = out
            process.standardError = out
            guard (try? process.run()) != nil else { return (127, "\(path) did not start") }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }
    }
#endif
