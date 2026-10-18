import Carbon.HIToolbox
import Foundation
import IOKit.hid
import IOKit.hidsystem
import Ink

/// Caps Lock, owned whole as a talk key: it types no capitals anywhere,
/// holding it is engaged while held, tapping it latches until the next tap
/// (Ink's `PushToTalk`, the mic button's grammar), and its own light says
/// when it is engaged.
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

    public let push = PushToTalk()
    /// Engaged (held or latched) changed; `push.latched` says which.
    public var onChange: ((_ engaged: Bool) -> Void)?
    /// What happened, for the host's log: armed, refused, light refused.
    public var onEvent: ((_ event: Event) -> Void)?

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

    private init() {
        push.onChange = { [weak self] engaged in
            guard let self else { return }
            self.light(engaged)
            self.onChange?(engaged)
        }
    }

    public func arm() {
        guard !armed else { return }
        guard Self.map([[Self.capsLock: Self.f18]]) else {
            onEvent?(.mappingRefused)
            return
        }
        let push = push
        let hotkey = PressReleaseHotkey(
            keyCode: UInt16(kVK_F18), carbonModifiers: 0,
            onPress: { push.pressBegan() }, onRelease: { push.pressEnded() })
        guard hotkey.registered else {
            _ = Self.map([])
            onEvent?(.f18Taken)
            return
        }
        self.hotkey = hotkey
        armed = true
        light(false)
        onEvent?(.armed)
    }

    public func disarm() {
        guard armed else { return }
        hotkey = nil
        push.stop()
        light(false)
        keyboards = nil
        armed = !Self.map([])
        onEvent?(.disarmed)
    }

    /// The Caps Lock LED on every keyboard that has one.
    private func light(_ on: Bool) {
        if keyboards == nil {
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerSetDeviceMatching(
                manager,
                [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard]
                    as CFDictionary)
            let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard opened == kIOReturnSuccess else {
                onEvent?(.lightRefused("keyboards not opened (\(String(opened, radix: 16))): Input Monitoring?"))
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
                    [kIOHIDElementUsagePageKey: kHIDPage_LEDs, kIOHIDElementUsageKey: kHIDUsage_LED_CapsLock]
                        as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] ?? []
            for led in leds {
                let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, led, 0, on ? 1 : 0)
                if IOHIDDeviceSetValue(device, led, value) == kIOReturnSuccess { lit += 1 }
            }
        }
        if lit == 0 { onEvent?(.lightRefused("no keyboard took the Caps Lock light")) }
    }

    /// Writes the HID system's key mapping: each pair maps a source usage to
    /// a destination usage on every keyboard. Read back to confirm.
    static func map(_ pairs: [[UInt64: UInt64]]) -> Bool {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let mapping = pairs.flatMap {
            $0.map { ["HIDKeyboardModifierMappingSrc": $0.key, "HIDKeyboardModifierMappingDst": $0.value] }
        }
        guard IOHIDEventSystemClientSetProperty(client, "UserKeyMapping" as CFString, mapping as CFArray)
        else { return false }
        let applied =
            IOHIDEventSystemClientCopyProperty(client, "UserKeyMapping" as CFString) as? [[String: UInt64]] ?? []
        return applied.count == mapping.count
    }
}
