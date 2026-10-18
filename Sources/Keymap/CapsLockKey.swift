import Carbon.HIToolbox
import Foundation
import IOKit.hid
import IOKit.hidsystem

/// Caps Lock, owned whole: it types no capitals anywhere, and says what the
/// hand did with it (`onHand`): down, then up as a hold or a tap. Its light is the host's to set
/// (`light(_:)`): the key knows hands and LEDs, the host knows what they
/// mean (a talk key: a tap switches the mic open, a hold talks while held,
/// the light shows the mic open).
///
/// How: the HID system maps Caps Lock to F18 on every keyboard (the public
/// `IOHIDEventSystemClient` "UserKeyMapping" property, the one hidutil
/// writes; it lasts until logout), so the key arrives as an ordinary one
/// with a press and a release, registered system-wide through Carbon (no
/// Accessibility). The light is the keyboard's Caps Lock LED element,
/// written through IOHIDManager; a Mac that refuses it (Input Monitoring
/// withheld) keeps a working key with no light, and says so.
///
/// One per process; `disarm()` gives Caps Lock back at once.
@MainActor
public final class CapsLockKey {
    public static let shared = CapsLockKey()

    /// Keyboard usage page 0x07: Caps Lock is 0x39, F18 is 0x6D.
    static let capsLock: UInt64 = 0x7_0000_0039
    static let f18: UInt64 = 0x7_0000_006D

    /// What the hand did: `down` at every press (a hold may be starting:
    /// act from the first instant), then `up`, a `tap` when the press was
    /// shorter than `holdThreshold`.
    public enum Hand: Sendable, Equatable {
        case down
        case up(tap: Bool)
    }

    /// Presses shorter than this are taps (Ink's `PushToTalk` measure).
    public var holdThreshold: TimeInterval = 0.35
    public var onHand: ((Hand) -> Void)?
    /// What happened, for the host's log: armed, refused, light refused.
    public var onEvent: ((_ event: Event) -> Void)?
    private var pressedAt: Date?

    public enum Event: Sendable, Equatable {
        case armed
        case disarmed
        case mappingRefused
        case f18Taken
        case lightRefused(String)
    }

    public private(set) var armed = false
    private var hotkey: PressReleaseHotkey?
    private var keyboards: IOHIDManager?
    /// The light's refusal is said once per arming; every press still
    /// tries, so a grant given meanwhile lights the next one.
    private var refusalSaid = false

    private init() {}

    private func pressed() {
        guard pressedAt == nil else { return }
        pressedAt = Date()
        onHand?(.down)
    }

    private func released() {
        guard let at = pressedAt else { return }
        pressedAt = nil
        onHand?(.up(tap: Date().timeIntervalSince(at) < holdThreshold))
    }

    public func arm() {
        guard !armed else { return }
        guard Self.map([[Self.capsLock: Self.f18]]) else {
            onEvent?(.mappingRefused)
            return
        }
        let hotkey = PressReleaseHotkey(
            keyCode: UInt16(kVK_F18), carbonModifiers: 0,
            onPress: { [weak self] in self?.pressed() },
            onRelease: { [weak self] in self?.released() })
        guard hotkey.registered else {
            _ = Self.map([])
            onEvent?(.f18Taken)
            return
        }
        self.hotkey = hotkey
        armed = true
        refusalSaid = false
        light(false)
        onEvent?(.armed)
    }

    public func disarm() {
        guard armed else { return }
        hotkey = nil
        pressedAt = nil
        light(false)
        keyboards = nil
        armed = !Self.map([])
        onEvent?(.disarmed)
    }

    /// The Caps Lock LED on every keyboard that has one: the host's state,
    /// shown on the key.
    public func light(_ on: Bool) {
        // Never open a keyboard before the person allowed it: an open
        // without access is recorded by macOS as a DENIAL, silently, and a
        // denied app is never prompted again (the request belongs to the
        // host's grant, asked by the person's own click).
        // Read the way the grant reads it (CoreGraphics, the WindowServer
        // route to tccd): one answer for the switch and the key.
        guard CGPreflightListenEventAccess() else {
            refused("Input Monitoring is not allowed yet: the light waits for it")
            return
        }
        if keyboards == nil {
            let manager = IOHIDManagerCreate(
                kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerSetDeviceMatching(
                manager,
                [
                    kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                    kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
                ]
                    as CFDictionary)
            let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard opened == kIOReturnSuccess else {
                refused(
                    "keyboards not opened (\(String(opened, radix: 16))): Input Monitoring is not allowed"
                )
                return
            }
            keyboards = manager
        }
        guard let keyboards else { return }
        var lit = 0
        for device in (IOHIDManagerCopyDevices(keyboards) as? Set<IOHIDDevice>) ?? [] {
            let leds =
                IOHIDDeviceCopyMatchingElements(
                    device,
                    [
                        kIOHIDElementUsagePageKey: kHIDPage_LEDs,
                        kIOHIDElementUsageKey: kHIDUsage_LED_CapsLock,
                    ]
                        as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]
                ?? []
            for led in leds {
                let value = IOHIDValueCreateWithIntegerValue(
                    kCFAllocatorDefault, led, 0, on ? 1 : 0)
                if IOHIDDeviceSetValue(device, led, value) == kIOReturnSuccess { lit += 1 }
            }
        }
        if lit == 0 { refused("no keyboard took the Caps Lock light") }
    }

    private func refused(_ why: String) {
        guard !refusalSaid else { return }
        refusalSaid = true
        onEvent?(.lightRefused(why))
    }

    /// Writes the HID system's key mapping: each pair maps a source usage to
    /// a destination usage on every keyboard. Read back to confirm.
    static func map(_ pairs: [[UInt64: UInt64]]) -> Bool {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let mapping = pairs.flatMap {
            $0.map {
                [
                    "HIDKeyboardModifierMappingSrc": $0.key,
                    "HIDKeyboardModifierMappingDst": $0.value,
                ]
            }
        }
        guard
            IOHIDEventSystemClientSetProperty(
                client, "UserKeyMapping" as CFString, mapping as CFArray)
        else { return false }
        let applied =
            IOHIDEventSystemClientCopyProperty(client, "UserKeyMapping" as CFString)
            as? [[String: UInt64]] ?? []
        return applied.count == mapping.count
    }
}
