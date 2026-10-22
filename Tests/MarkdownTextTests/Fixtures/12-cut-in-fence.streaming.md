Yes, `BiometricLock` in the Biometrics module is exactly that:

```swift
import Biometrics

BiometricLock(
    title: "This Vault Is Locked",
    subtitle: "Touch ID or enter the password to open it.",
    reason: "unlock the vault"
) { verdict in
    switch verdict {
    case .biometry(let context): unlock(with: con