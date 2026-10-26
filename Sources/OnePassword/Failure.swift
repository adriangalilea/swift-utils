#if os(macOS)
    import Foundation

    extension OnePasswordCLI {
        /// Why a run gave nothing, each saying what a person does next. What
        /// `op` said rides along (`said`), with anything secret taken out
        /// (`redacted`): a token, and text quoted back from its stdin.
        public enum Failure: Error, Sendable, Equatable, CustomStringConvertible {
            /// No `op` in any of the folders `searched`.
            case notInstalled(searched: [String])
            /// The `op` at `path` is not AgileBits' (or its signature could
            /// not be read): killed before it ran.
            case notAgileBits(path: String, why: String)
            /// `op` could not be started at all (a pipe, the spawn, its home).
            case couldNotStart(path: String, why: String)
            /// No account to act as: the app has none, is not connected to the
            /// command line, or the service account's token is bad.
            case noAccount(Mode.Access, said: String)
            /// The person said no in 1Password, or did not answer its prompt.
            case refused(said: String)
            /// 1Password's caps on requests are spent until they reset.
            case rateLimited(said: String)
            /// The item, vault, field or document asked for is not there (or
            /// not visible to this account).
            case notFound(said: String)
            /// `op` did not finish within the run's timeout: stopped.
            case timedOut(after: Duration)
            /// Anything else `op` refused: what it said, else how it ended.
            case failed(said: String)

            public var description: String {
                switch self {
                case .notInstalled(let searched):
                    "1Password's command line (op) is not installed (looked in \(searched.joined(separator: ", "))): brew install 1password-cli"
                case .notAgileBits(let path, let why):
                    "\(path) is not 1Password's op (\(why)): not run. Reinstall it (brew reinstall 1password-cli) and remove whatever replaced it"
                case .couldNotStart(let path, let why):
                    "\(path) could not be started: \(why)"
                case .noAccount(.app, let said):
                    "1Password's command line reaches no account (\(said)): open 1Password, sign in, and turn on Settings › Developer › Integrate with 1Password CLI"
                case .noAccount(.serviceAccount, let said):
                    "1Password does not accept this service account (\(said)): its token is wrong or revoked; make a new one and connect it again"
                case .refused(let said):
                    "declined in 1Password (\(said)): nothing was done; ask again and approve it in 1Password"
                case .rateLimited(let said):
                    "1Password refuses for now (\(said)): a cap on requests is spent; wait for it to reset (op service-account ratelimit shows when)"
                case .notFound(let said):
                    "not in 1Password (\(said)): check the reference, and that this account can see that vault"
                case .timedOut(let after):
                    "1Password did not answer within \(after.formatted(.units(allowed: [.minutes, .seconds]))): stopped; try again"
                case .failed(let said): "op failed: \(said)"
                }
            }

            /// The case's name, for the log's `outcome`.
            var name: String {
                switch self {
                case .notInstalled: "notInstalled"
                case .notAgileBits: "notAgileBits"
                case .couldNotStart: "couldNotStart"
                case .noAccount: "noAccount"
                case .refused: "refused"
                case .rateLimited: "rateLimited"
                case .notFound: "notFound"
                case .timedOut: "timedOut"
                case .failed: "failed"
                }
            }

            /// What an `op` that ended badly said, read into a case. The
            /// phrases are `op`'s own (2.39.0's binary; Authz and hollow read
            /// the same), matched in this order: a rate limit can come with
            /// any other words.
            static func reading(_ said: String, access: Mode.Access) -> Failure {
                func says(_ phrases: String...) -> Bool { phrases.contains { said.contains($0) } }
                if says("Too many requests", "rate-limited", "rate limit exceeded") {
                    return .rateLimited(said: said)
                }
                if says(
                    "No accounts configured for use with 1Password CLI",
                    "You are not currently signed in",
                    "account is not signed in", "bad service account token",
                    "service account token had invalid format",
                    "service account token base64 decoding failed")
                {
                    return .noAccount(access, said: said)
                }
                if says("authorization prompt dismissed", "authorization timeout") {
                    return .refused(said: said)
                }
                if says(
                    "isn't an item", "isn't a vault in this account", "isn't a field in the",
                    "document not found in item")
                {
                    return .notFound(said: said)
                }
                return .failed(said: said)
            }

            /// `op`'s stderr for a person: each line without its
            /// `[ERROR] 2026/10/26 12:00:00 ` stamp, then `redacted`.
            static func cleaned(_ stderr: Data, token: String?, input: Data?) -> String {
                let text = String(decoding: stderr, as: UTF8.self)
                let lines = text.split(whereSeparator: { $0.isNewline }).map { line in
                    String(
                        line.replacing(
                            #/^\[[A-Z]+\] \d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} /#, with: ""))
                }
                let joined = lines.joined(separator: "\n").trimmingCharacters(
                    in: .whitespacesAndNewlines)
                return redacted(joined, token: token, input: input)
            }

            /// Anything secret out of `text`: the run's token, any service
            /// account token (`ops_…`), and any quoted passage (`"…"`, `'…'`,
            /// `` `…` ``) found verbatim in the run's stdin, which is where a
            /// secret was handed to `op`.
            static func redacted(_ text: String, token: String?, input: Data?) -> String {
                var text = text
                if let token, !token.isEmpty { text = text.replacing(token, with: "<redacted>") }
                text = text.replacing(#/ops_[A-Za-z0-9+\/=_-]{8,}/#, with: "<redacted>")
                guard let input, !input.isEmpty else { return text }
                let given = String(decoding: input, as: UTF8.self)
                return text.replacing(#/"([^"]+)"|'([^']+)'|`([^`]+)`/#) { match in
                    let quoted = String(match.output.1 ?? match.output.2 ?? match.output.3 ?? "")
                    return given.contains(quoted) ? "<redacted>" : String(match.output.0)
                }
            }
        }
    }
#endif
