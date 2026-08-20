import Foundation
import OpenDirectory

// Safari's curtain field verifies the LOGIN password ("enter the password
// for the user X to view locked tabs") - the public API for that is
// OpenDirectory's verifyPassword on the local authentication node. This is
// what makes a Door's typed fallback REAL for apps that gate nothing
// keychain-bound: no app password to invent, the user's own password.
// UNSANDBOXED apps only - the sandbox has no OpenDirectory access.
public enum LoginPassword {
    public static func verify(_ typed: String) -> Bool {
        guard
            let node = try? ODNode(
                session: .default(), type: ODNodeType(kODNodeTypeAuthentication)),
            let record = try? node.record(
                withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
        else { return false }
        return (try? record.verifyPassword(typed)) != nil
    }

    /// The name for the subtitle ("enter the password for NAME").
    public static var userDisplayName: String { NSFullUserName() }
}
