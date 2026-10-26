import CoreServices
import Foundation
import GitKit

#if os(macOS)
    extension Git.LocalSource {
        /// FSEvents on the working tree and the repository's git folders (a linked
        /// worktree keeps its HEAD and index outside the tree). A burst of writes is
        /// one batch (`Watch.latency`, FSEvents' own coalescing); after each batch the
        /// repository is read as a reader would see it (`Watch.Fingerprint`: status,
        /// refs, and each changed file's size and time), and only a different reading
        /// yields. A build churning an ignored folder costs one status and yields
        /// nothing. Ends when the reader stops iterating. Watching from its return: it
        /// reads the repository first (two git runs), so call it off the main thread.
        public func changes() -> AsyncStream<Void> {
            AsyncStream { continuation in
                let watch = Watch(source: self, continuation: continuation)
                continuation.onTermination = { _ in watch.stop() }
                watch.start()
            }
        }
    }

    /// One repository watched for `LocalSource.changes()`.
    final class Watch: @unchecked Sendable {
        /// How long FSEvents gathers writes into one batch, in seconds.
        static let latency: CFTimeInterval = 0.3
        /// Changed files whose size and time count toward a reading, at most.
        static let statLimit = 2000

        private let source: Git.LocalSource
        private let continuation: AsyncStream<Void>.Continuation
        private let queue = DispatchQueue(label: "gitlocal.watch")
        private var stream: FSEventStreamRef?
        private var last: Data?
        /// Paths under these say nothing a reader shows (objects are written before
        /// the ref that names them, logs beside every ref move).
        private var quiet: [String] = []

        init(source: Git.LocalSource, continuation: AsyncStream<Void>.Continuation) {
            self.source = source
            self.continuation = continuation
        }

        func start() {
            queue.sync { [self] in
                let root = source.repository.resolvingSymlinksInPath().path
                var folders = [root]
                for flag in ["--absolute-git-dir", "--git-common-dir"] {
                    guard
                        let data = try? Git.LocalSource.run(
                            ["rev-parse", "--path-format=absolute", flag], in: source.repository,
                            allowing: []),
                        let line = String(data: data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty
                    else { continue }
                    let folder = URL(filePath: line).resolvingSymlinksInPath().path
                    quiet += [folder + "/objects/", folder + "/logs/"]
                    if !folders.contains(where: { folder == $0 || folder.hasPrefix($0 + "/") }) {
                        folders.append(folder)
                    }
                }
                last = fingerprint()
                var context = FSEventStreamContext(
                    version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil,
                    release: nil, copyDescription: nil)
                guard
                    let stream = FSEventStreamCreate(
                        nil, Watch.callback, &context, folders as CFArray,
                        FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Watch.latency,
                        FSEventStreamCreateFlags(
                            kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot))
                else {
                    continuation.finish()
                    return
                }
                FSEventStreamSetDispatchQueue(stream, queue)
                FSEventStreamStart(stream)
                self.stream = stream
            }
        }

        /// The stream holds `self` unretained: it is stopped and released on its queue,
        /// by a closure that keeps the watch alive until then (a finish on the queue
        /// itself ends the reader too, so this never waits for the queue).
        func stop() {
            queue.async { [self] in
                guard let stream else { return }
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
        }

        private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watch = Unmanaged<Watch>.fromOpaque(info).takeUnretainedValue()
            let names = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            let batch = (0..<count).map { String(cString: names[$0]) }
            let rootGone = (0..<count).contains {
                flags[$0] & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
            }
            watch.batch(batch, rootGone: rootGone)
        }

        /// On the queue: a batch read, yielded when the reading moved.
        private func batch(_ paths: [String], rootGone: Bool) {
            guard stream != nil else { return }
            if rootGone {
                continuation.yield()
                continuation.finish()
                return
            }
            guard paths.contains(where: { path in !quiet.contains { path.hasPrefix($0) } }) else {
                return
            }
            let now = fingerprint()
            guard now != last else { return }
            last = now
            continuation.yield()
        }

        /// The repository as a reader sees it: status (HEAD, branch, every changed path),
        /// every ref, and each changed file's size and modification time, so a second
        /// edit of a file already modified reads as a change.
        private func fingerprint() -> Data? {
            let folder = source.repository
            guard
                let status = try? Git.LocalSource.run(
                    Git.Command.status(), in: folder, allowing: []),
                let refs = try? Git.LocalSource.run(
                    Git.Command.branches(), in: folder, allowing: [])
            else { return nil }
            var reading = status + refs
            let paths =
                (try? Git.Status(parsing: status))?.groups.flatMap { $0.files.map(\.path) } ?? []
            for path in paths.prefix(Watch.statLimit) {
                var info = stat()
                guard stat(folder.appending(path: path).path, &info) == 0 else { continue }
                withUnsafeBytes(of: info.st_size) { reading.append(contentsOf: $0) }
                withUnsafeBytes(of: info.st_mtimespec.tv_sec) { reading.append(contentsOf: $0) }
                withUnsafeBytes(of: info.st_mtimespec.tv_nsec) { reading.append(contentsOf: $0) }
            }
            return reading
        }
    }
#endif
