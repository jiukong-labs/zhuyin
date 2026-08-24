import AppKit
import Carbon

enum ShiftKeySide: Hashable {
    case left
    case right

    var deviceModifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .left:
            return NSEvent.ModifierFlags(
                rawValue: UInt(NX_DEVICELSHIFTKEYMASK)
            )
        case .right:
            return NSEvent.ModifierFlags(
                rawValue: UInt(NX_DEVICERSHIFTKEYMASK)
            )
        }
    }

    init?(keyCode: UInt16) {
        switch Int(keyCode) {
        case kVK_Shift:
            self = .left
        case kVK_RightShift:
            self = .right
        default:
            return nil
        }
    }
}

enum ShiftKeyPreference: String, CaseIterable, Codable, Equatable {
    case both
    case left
    case right
    case disabled

    func allows(_ side: ShiftKeySide) -> Bool {
        switch (self, side) {
        case (.both, _), (.left, .left), (.right, .right):
            return true
        case (.left, .right), (.right, .left), (.disabled, _):
            return false
        }
    }
}

/// Distinguishes a standalone Shift tap from a Shift-modified key chord.
struct ShiftToggleController {
    private static let disallowedChordModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .function,
        .option
    ]
    private static let deviceShiftModifiers: NSEvent.ModifierFlags = [
        .init(rawValue: UInt(NX_DEVICELSHIFTKEYMASK)),
        .init(rawValue: UInt(NX_DEVICERSHIFTKEYMASK))
    ]

    private var pressedShiftKeys: Set<ShiftKeySide> = []
    private var toggleCandidate: ShiftKeySide?
    private var wasInterrupted = false
    /// Some clients deliver a Shift release to the input method before the
    /// key-down event for the Shift chord. Sampling WindowServer's monotonic
    /// event counter at both edges keeps standalone-tap detection independent
    /// of that client delivery order.
    private var keyDownEventCountAtPress: UInt32?

    var isTrackingShift: Bool {
        !pressedShiftKeys.isEmpty
    }

    /// Returns true only when this event completes an eligible standalone tap.
    mutating func handleFlagsChanged(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        preference: ShiftKeyPreference = .both,
        systemKeyDownEventCount: UInt32? = nil
    ) -> Bool {
        guard let side = ShiftKeySide(keyCode: keyCode) else {
            noteNonShiftModifierChange()
            return false
        }

        let hasDisallowedModifier = !modifierFlags
            .intersection(Self.disallowedChordModifiers)
            .isEmpty

        if pressedShiftKeys.contains(side) {
            // Some web-backed clients can deliver the same Shift-down change
            // more than once while the key is still physically held. Do not
            // mistake that duplicate for Shift-up and toggle before a letter
            // arrives. Device-specific flags distinguish the two Shift keys;
            // the generic fallback covers clients that strip those bits.
            if isStillPressed(
                side,
                modifierFlags: modifierFlags
            ) {
                if hasDisallowedModifier {
                    wasInterrupted = true
                }
                return false
            }

            if hasDisallowedModifier {
                wasInterrupted = true
            }
            if let keyDownEventCountAtPress,
               let systemKeyDownEventCount,
               systemKeyDownEventCount != keyDownEventCountAtPress {
                wasInterrupted = true
            }
            pressedShiftKeys.remove(side)
            let shouldToggle = toggleCandidate == side
                && !wasInterrupted
                && pressedShiftKeys.isEmpty
                && preference.allows(side)
            if pressedShiftKeys.isEmpty {
                clearGesture()
            } else {
                wasInterrupted = true
            }
            return shouldToggle
        }

        // A controller can be activated while Shift is already held. A lone
        // release in that situation must never be mistaken for a complete tap.
        guard modifierFlags.contains(.shift) else {
            if pressedShiftKeys.isEmpty {
                clearGesture()
            }
            return false
        }

        if pressedShiftKeys.isEmpty {
            toggleCandidate = side
            wasInterrupted = hasDisallowedModifier
            keyDownEventCountAtPress = systemKeyDownEventCount
        } else {
            wasInterrupted = true
        }
        pressedShiftKeys.insert(side)
        return false
    }

    mutating func noteKeyDown() {
        guard isTrackingShift else {
            return
        }
        wasInterrupted = true
    }

    mutating func noteNonShiftModifierChange() {
        guard isTrackingShift else {
            return
        }
        wasInterrupted = true
    }

    mutating func reset() {
        pressedShiftKeys.removeAll()
        clearGesture()
    }

    private mutating func clearGesture() {
        toggleCandidate = nil
        wasInterrupted = false
        keyDownEventCountAtPress = nil
    }

    private func isStillPressed(
        _ side: ShiftKeySide,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        let deviceShiftFlags = modifierFlags.intersection(
            Self.deviceShiftModifiers
        )
        if !deviceShiftFlags.isEmpty {
            return deviceShiftFlags.contains(side.deviceModifierFlag)
        }

        // With only the device-independent Shift flag, a single tracked key
        // is still down. If both sides are tracked, an event for one side can
        // be its release while the other side keeps `.shift` set.
        return modifierFlags.contains(.shift) && pressedShiftKeys.count == 1
    }
}
