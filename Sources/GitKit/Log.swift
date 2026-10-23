import Foundation

extension Git {
    /// A commit as `Commit.format` writes it.
    public struct Commit: Codable, Sendable, Hashable, Identifiable {
        public struct Signature: Codable, Sendable, Hashable {
            public var name: String
            public var email: String
            public var date: Date
            public init(name: String, email: String, date: Date) {
                self.name = name
                self.email = email
                self.date = date
            }
        }

        public var hash: String
        public var parents: [String]
        public var author: Signature
        public var committer: Signature
        /// The refs pointing here, as `%D` writes them (`HEAD -> main`, `origin/main`,
        /// `tag: v1.0`).
        public var refs: [String]
        public var subject: String
        public var body: String

        public init(
            hash: String, parents: [String], author: Signature, committer: Signature,
            refs: [String] = [],
            subject: String, body: String = ""
        ) {
            self.hash = hash
            self.parents = parents
            self.author = author
            self.committer = committer
            self.refs = refs
            self.subject = subject
            self.body = body
        }

        public var id: String { hash }
        public var shortHash: String { String(hash.prefix(7)) }
        public var isMerge: Bool { parents.count > 1 }

        /// `git log --format=<this>`: the fields NUL-separated, each record ended by RS
        /// (0x1E), so a subject or body can hold anything but those two bytes.
        public static let format =
            "%H%x00%P%x00%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI%x00%D%x00%s%x00%b%x1E"

        /// Records as `format` writes them.
        public static func parse(_ data: Data) throws -> [Commit] {
            var out: [Commit] = []
            for (index, record) in Git.records(data, separator: 0x1E).enumerated() {
                let trimmed = record.drop { $0 == "\n" }
                if trimmed.isEmpty { continue }
                let fields = trimmed.split(separator: "\0", omittingEmptySubsequences: false)
                guard fields.count >= 11,
                    let authored = date(fields[4]), let committed = date(fields[7])
                else {
                    throw ParseError.record(
                        kind: "log", line: index + 1, text: String(trimmed.prefix(120)))
                }
                out.append(
                    Commit(
                        hash: String(fields[0]),
                        parents: fields[1].split(separator: " ").map(String.init),
                        author: Signature(
                            name: String(fields[2]), email: String(fields[3]), date: authored),
                        committer: Signature(
                            name: String(fields[5]), email: String(fields[6]), date: committed),
                        refs: fields[8].isEmpty ? [] : fields[8].components(separatedBy: ", "),
                        subject: String(fields[9]),
                        body: fields[10...].joined(separator: "\0").trimmingCharacters(
                            in: .whitespacesAndNewlines)))
            }
            return out
        }

        static func date(_ text: Substring) -> Date? {
            try? Date(String(text), strategy: .iso8601)
        }
    }
}
