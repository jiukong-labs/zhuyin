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
    struct GestureConclusion {
        var side: ShiftKeySide
        var pressTime: TimeInterval
        var releaseTime: TimeInterval
        /// A counter sampled in a delayed callback may include keys pressed
        /// after release. A completed polling tap can resolve that ambiguity;
        /// an explicitly observed chord must still reject the gesture.
        var allowsFallbackRecovery: Bool
        /// Both delivered edges observed the physical key already released,
        /// with no intervening modifier event. This is a limited correlation
        /// hint, not a claim that every client event carries a physical ID.
        var observedReleaseCounter: UInt32? = nil
    }

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
    /// event counter at both edges can reject that chord, but a delayed
    /// release callback can also see keys typed after release. Keep that
    /// ambiguous rejection separate from a chord observed by this tracker.
    private var keyDownEventCountAtPress: UInt32?
    private var releasedModifierCountAtPress: UInt32?
    private var pressTime: TimeInterval?
    private(set) var concludedGesture: GestureConclusion?

    var isTrackingShift: Bool {
        !pressedShiftKeys.isEmpty
    }

    /// Returns true only when this event completes an eligible standalone tap.
    mutating func handleFlagsChanged(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        preference: ShiftKeyPreference = .both,
        systemKeyDownEventCount: UInt32? = nil,
        systemFlagsChangedEventCount: UInt32? = nil,
        systemShiftIsPressed: Bool? = nil,
        eventTimestamp: TimeInterval? = nil
    ) -> Bool {
        concludedGesture = nil
        guard let side = ShiftKeySide(keyCode: keyCode) else {
            noteNonShiftModifierChange(
                systemShiftIsPressed: systemShiftIsPressed
            )
            return false
        }

        let hasDisallowedModifier = !modifierFlags
            .intersection(Self.disallowedChordModifiers)
            .isEmpty

        if pressedShiftKeys.contains(side) {
            // Some web-backed clients can deliver the same Shift-down change
            // more than once while the key is still physically held. Do not
            // mistake that duplicate for Shift-up and toggle before a letter
            // arrives. Device-specific flags distinguish the two Shift keys.
            // When a client strips those bits, trust WindowServer's current
            // modifier state instead of the event's generic `.shift` bit: on
            // newer macOS releases that bit can remain set on a release event.
            if isStillPressed(
                side,
                modifierFlags: modifierFlags,
                systemShiftIsPressed: systemShiftIsPressed
            ) {
                if hasDisallowedModifier {
                    wasInterrupted = true
                }
                return false
            }

            if hasDisallowedModifier {
                wasInterrupted = true
            }
            let counterChanged: Bool
            if let keyDownEventCountAtPress, let systemKeyDownEventCount {
                counterChanged = systemKeyDownEventCount != keyDownEventCountAtPress
            } else {
                counterChanged = false
            }
            pressedShiftKeys.remove(side)
            let eligible = toggleCandidate == side
                && !wasInterrupted
                && pressedShiftKeys.isEmpty
                && preference.allows(side)
            let shouldToggle = eligible && !counterChanged
            if pressedShiftKeys.isEmpty {
                if let pressTime, let eventTimestamp {
                    concludedGesture = GestureConclusion(
                        side: side,
                        pressTime: pressTime,
                        releaseTime: eventTimestamp,
                        allowsFallbackRecovery: eligible && counterChanged,
                        observedReleaseCounter:
                            systemShiftIsPressed == false
                                && releasedModifierCountAtPress == systemFlagsChangedEventCount
                            ? releasedModifierCountAtPress : nil
                    )
                }
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
            releasedModifierCountAtPress = systemShiftIsPressed == false
                ? systemFlagsChangedEventCount : nil
            pressTime = eventTimestamp
        } else {
            wasInterrupted = true
        }
        pressedShiftKeys.insert(side)
        return false
    }

    mutating func noteKeyDown(systemShiftIsPressed: Bool? = nil) {
        guard isTrackingShift else {
            return
        }

        // If macOS omitted the Shift release entirely, do not let the stale
        // gesture poison every later Shift tap. A non-Shift key-down while
        // WindowServer says Shift is already up is sufficient proof that the
        // tracked press is stale.
        guard currentSystemShiftIsPressed(
            reportedState: systemShiftIsPressed
        ) else {
            reset()
            return
        }

        wasInterrupted = true
    }

    mutating func noteNonShiftModifierChange(
        systemShiftIsPressed: Bool? = nil
    ) {
        guard isTrackingShift else {
            return
        }

        if !currentSystemShiftIsPressed(reportedState: systemShiftIsPressed) {
            reset()
            return
        }

        wasInterrupted = true
    }

    mutating func reset() {
        pressedShiftKeys.removeAll()
        concludedGesture = nil
        clearGesture()
    }

    /// The polling path completed a tap whose release the client may never
    /// deliver. Forget that stale press, but preserve a newer physical press
    /// already delivered while the earlier tap waited for arbitration.
    mutating func recoveredTap(releasedAt time: TimeInterval) {
        if let pressTime, pressTime <= time {
            reset()
        }
    }

    private mutating func clearGesture() {
        toggleCandidate = nil
        wasInterrupted = false
        keyDownEventCountAtPress = nil
        releasedModifierCountAtPress = nil
        pressTime = nil
    }

    private func isStillPressed(
        _ side: ShiftKeySide,
        modifierFlags: NSEvent.ModifierFlags,
        systemShiftIsPressed: Bool?
    ) -> Bool {
        let deviceShiftFlags = modifierFlags.intersection(
            Self.deviceShiftModifiers
        )
        if !deviceShiftFlags.isEmpty {
            return deviceShiftFlags.contains(side.deviceModifierFlag)
        }

        // An ordinary release clears every Shift bit the event carries, and
        // that is the reliable answer: the event describes the instant the key
        // moved, while the system's modifier state describes now. A second tap
        // can already have pushed Shift back down by the time this release is
        // handled, so consulting the system here would read that later press
        // as this key never having come up and swallow the toggle.
        guard modifierFlags.contains(.shift) else {
            return false
        }

        // With both sides tracked, a generic Shift state cannot tell which
        // side changed. Preserve the old behavior and treat this event as that
        // side's release while the other side keeps Shift active.
        if pressedShiftKeys.count > 1 {
            return false
        }

        // Only an event that still claims Shift reaches here. That claim is
        // what newer macOS releases can leave stale on a release, so the
        // system's own modifier state is the better answer for it.
        return currentSystemShiftIsPressed(
            reportedState: systemShiftIsPressed
        )
    }

    private func currentSystemShiftIsPressed(
        reportedState: Bool?
    ) -> Bool {
        if let reportedState {
            return reportedState
        }
        return CGEventSource.flagsState(.combinedSessionState)
            .contains(.maskShift)
    }
}

extension ShiftToggleController {
    /// Read-only snapshot of the gesture bookkeeping, for diagnostic logging.
    /// Same-file access keeps the stored properties private to the type.
    var diagnosticState: String {
        let sides = pressedShiftKeys
            .map { $0 == .left ? "L" : "R" }
            .sorted()
            .joined()
        let candidate = toggleCandidate
            .map { $0 == .left ? "L" : "R" } ?? "-"
        let counter = keyDownEventCountAtPress
            .map(String.init) ?? "-"
        return "held=\(sides.isEmpty ? "-" : sides)"
            + " candidate=\(candidate)"
            + " interrupted=\(wasInterrupted)"
            + " kdAtPress=\(counter)"
    }
}
