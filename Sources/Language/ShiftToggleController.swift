import AppKit
import Carbon

enum ShiftKeySide: Hashable {
    case left
    case right

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
}
