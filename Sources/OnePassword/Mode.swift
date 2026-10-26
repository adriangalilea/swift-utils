#if os(macOS)
    import Darwin
    import Foundation

    extension OnePasswordCLI {
        /// Who `op` acts as, and the whole environment it gets for that. Both
        /// give it a HOME of the app's own (`home`): under the person's real
        /// one, `op` reads 1Password's settings in its group container, which
        /// macOS charges to the app running it as "data from other apps".
        ///
        /// Holds a service account's token without ever showing it: printed,
        /// dumped or interpolated it reads `serviceAccount(token: <redacted>)`.
        public struct Mode: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
            CustomReflectable
        {
            /// Which of the two, without the token.
            public enum Access: String, Sendable, Equatable {
                /// A service account: a token, no app, no person.
                case serviceAccount
                /// The person's own 1Password app, which asks them.
                case app
            }

            public let access: Access
            /// `op`'s HOME: a folder of the app's own, made (0700) on the
            /// first run if missing. Never the person's real home.
            public let home: URL
            let token: String?

            /// As a service account: `token` goes to `op` in its environment
            /// for each run and nowhere else. No 1Password app, no unlock, no
            /// macOS data-access consent; read and write only what the account
            /// was granted.
            public static func serviceAccount(token: String, home: URL) -> Mode {
                precondition(!token.isEmpty, "a service account needs its token")
                return Mode(access: .serviceAccount, home: checked(home), token: token)
            }

            /// Through the person's own 1Password app, over XPC: 1Password asks
            /// them (Touch ID, or its password) for each run that needs it.
            /// Needs 1Password › Settings › Developer › Integrate with
            /// 1Password CLI. `op` is told the integration is on
            /// (`OP_BIOMETRIC_UNLOCK_ENABLED`) instead of reading 1Password's
            /// settings, which a GUI app is denied without a prompt (README).
            public static func app(home: URL) -> Mode {
                Mode(access: .app, home: checked(home), token: nil)
            }

            /// Exactly what `op` gets, nothing inherited from this process
            /// (whose `OP_*`, proxies or a parent's session must not reach it):
            ///
            /// - `HOME`, `XDG_CONFIG_HOME`: the app's own folder, so `op`
            ///   reads and writes its config there and never under the
            ///   person's home (1Password's group container).
            /// - `PATH`: the system's folders only; `op` finds nothing of the
            ///   user's.
            /// - `USER`, `LOGNAME`: this account, from the password database.
            /// - `TMPDIR`: this account's temporary folder, from the system
            ///   (`op document get` and its like write there).
            /// - `LANG`: `en_US.UTF-8`, so `op`'s messages are the English ones
            ///   `Failure` reads.
            /// - A service account: `OP_SERVICE_ACCOUNT_TOKEN`, and
            ///   `OP_CACHE=false` (no cache daemon forked per call: the caller
            ///   is the cache).
            /// - The app: `OP_BIOMETRIC_UNLOCK_ENABLED=true`.
            var environment: [String: String] {
                let account = Self.account
                var environment = [
                    "HOME": home.path,
                    "XDG_CONFIG_HOME": home.appending(path: ".config").path,
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                    "USER": account.name,
                    "LOGNAME": account.name,
                    "TMPDIR": Self.temporaryFolder,
                    "LANG": "en_US.UTF-8",
                ]
                switch access {
                case .serviceAccount:
                    environment["OP_SERVICE_ACCOUNT_TOKEN"] = token
                    environment["OP_CACHE"] = "false"
                case .app:
                    environment["OP_BIOMETRIC_UNLOCK_ENABLED"] = "true"
                }
                return environment
            }

            public var description: String {
                switch access {
                case .serviceAccount: "serviceAccount(token: <redacted>, home: \(home.path))"
                case .app: "app(home: \(home.path))"
                }
            }
            public var debugDescription: String { description }
            public var customMirror: Mirror {
                Mirror(self, children: ["access": access, "home": home], displayStyle: .struct)
            }

            /// This process's account, from the password database (never the
            /// environment, which anyone starting this process chose).
            static var account: (name: String, home: String) {
                guard let entry = getpwuid(getuid()) else {
                    preconditionFailure("this process's uid \(getuid()) has no password entry")
                }
                return (
                    String(cString: entry.pointee.pw_name), String(cString: entry.pointee.pw_dir)
                )
            }

            /// This account's temporary folder, as the system names it.
            static var temporaryFolder: String {
                var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
                let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
                precondition(length > 0 && length <= buffer.count, "no per-user temporary folder")
                return String(
                    decoding: buffer.prefix(length - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self
                )
            }

            /// A HOME of the app's own, never the person's real one: that
            /// would hand `op` 1Password's group container again.
            private static func checked(_ home: URL) -> URL {
                precondition(home.isFileURL, "op's home must be a folder: \(home)")
                let path = home.standardizedFileURL.resolvingSymlinksInPath().path
                let real = URL(filePath: account.home).standardizedFileURL.resolvingSymlinksInPath()
                    .path
                precondition(
                    path != real && path != "/",
                    "op's home must be a folder of the app's own, not \(path)")
                return home
            }
        }
    }
#endif
