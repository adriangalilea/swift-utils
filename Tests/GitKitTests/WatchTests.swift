import Foundation
import GitKit
import GitLocal
import Testing

/// `LocalSource.changes()` on a real repository made for the test: a write the reader
/// would see yields, a write in an ignored folder does not, and the reader ending stops
/// the watch.
struct WatchTests {
    private func git(_ folder: URL, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments =
            ["-C", folder.path, "-c", "user.name=t", "-c", "user.email=t@t"] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "git \(arguments.joined(separator: " "))")
    }

    /// The next element, or false once `seconds` pass without one.
    private func next(_ changes: AsyncStream<Void>, within seconds: Double) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = changes.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    @Test func aWriteTheReaderSeesYieldsAndAnIgnoredOneDoesNot() async throws {
        let folder = URL(filePath: NSTemporaryDirectory()).appending(
            path: "watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try git(folder, "init", "-q")
        try "build/\n".write(
            to: folder.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try "one\n".write(to: folder.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try git(folder, "add", ".")
        try git(folder, "commit", "-q", "-m", "genesis")
        try FileManager.default.createDirectory(
            at: folder.appending(path: "build"), withIntermediateDirectories: true)

        let source = Git.LocalSource(repository: folder)
        // Watching from the moment `changes()` returns.
        let changes = source.changes()
        try "artifact\n".write(
            to: folder.appending(path: "build/out.o"), atomically: true, encoding: .utf8)
        #expect(await next(changes, within: 2) == false, "an ignored write yielded")

        let watched = source.changes()
        try "two\n".write(to: folder.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        #expect(await next(watched, within: 5), "a modified file did not yield")
    }
}
