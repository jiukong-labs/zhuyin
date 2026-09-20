import Foundation

/// One reading of the session's keyboard state, taken by polling instead of
/// from events a client decided to forward.
///
/// Some observed client sessions deliver ordinary key-downs while omitting
/// Shift `flagsChanged` events. WindowServer's session state provides an
/// independent observation of the gesture without assuming which layer lost it.
struct SystemKeyboardSample: Equatable {
    /// When the most recent modifier change happened, in seconds since system
    /// startup, the clock `NSEvent.timestamp` uses. Unlike the moment a sample
    /// is taken, this does not drift with how late the poll ran.
    var lastModifierChangeTime: TimeInterval
    /// Side-specific Shift state. A Shift reported without a side counts as
    /// neither, so it can never produce a tap for the wrong side.
    var leftShiftDown: Bool
    var rightShiftDown: Bool
    /// Command, Control, Option or Function held at this instant.
    var otherModifierDown: Bool
    /// Session-wide event counters. They advance even for events that land
    /// between two samples, so a chord typed faster than the polling interval
    /// still shows up.
    var keyDownCount: UInt32
    var mouseDownCount: UInt32
    var flagsChangedCount: UInt32
}

/// A standalone Shift tap recovered from keyboard state.
struct SystemShiftTap: Equatable {
    var side: ShiftKeySide
    /// When this Shift key was pressed, on the `NSEvent.timestamp` clock.
    var pressTime: TimeInterval
    /// When the Shift key was released, on the `NSEvent.timestamp` clock.
    var releaseTime: TimeInterval
}

/// Recognizes standalone Shift taps from successive keyboard-state samples.
///
/// A tap qualifies only when exactly one Shift key went down and came back up
/// with nothing else in between: no key-down, no mouse click, no other
/// modifier, and no modifier change beyond that Shift press and release.
struct SystemShiftTapDetector {
    private struct Baseline {
        var pressTime: TimeInterval
        var keyDownCount: UInt32
        var mouseDownCount: UInt32
        var flagsChangedCount: UInt32
    }

    private var previous: SystemKeyboardSample?
    private var candidate: ShiftKeySide?
    private var isInterrupted = false
    private var baseline: Baseline?

    mutating func reset() {
        previous = nil
        clearGesture()
    }

    /// Feeds the next sample and returns a tap when this sample completes one.
    mutating func ingest(_ sample: SystemKeyboardSample) -> SystemShiftTap? {
        defer { previous = sample }

        let isShiftDown = sample.leftShiftDown || sample.rightShiftDown
        guard let previous else {
            // Polling can start while Shift is already held. That press was
            // never observed, so its release must not count as a tap.
            if isShiftDown {
                candidate = nil
                isInterrupted = true
            }
            return nil
        }

        let wasShiftDown = previous.leftShiftDown || previous.rightShiftDown

        switch (wasShiftDown, isShiftDown) {
        case (false, true):
            beginGesture(with: sample, after: previous)
            return nil
        case (true, true):
            continueGesture(with: sample, after: previous)
            return nil
        case (true, false):
            defer { clearGesture() }
            return completedTap(at: sample)
        case (false, false):
            return nil
        }
    }

    private mutating func beginGesture(
        with sample: SystemKeyboardSample,
        after previous: SystemKeyboardSample
    ) {
        // Measure from the last sample with Shift up. A key typed within the
        // same polling interval as the Shift press then counts against the
        // tap, which errs toward not switching over switching mid-word.
        baseline = Baseline(
            pressTime: sample.lastModifierChangeTime,
            keyDownCount: previous.keyDownCount,
            mouseDownCount: previous.mouseDownCount,
            flagsChangedCount: previous.flagsChangedCount
        )

        if sample.leftShiftDown && sample.rightShiftDown {
            candidate = nil
            isInterrupted = true
            return
        }

        candidate = sample.leftShiftDown ? .left : .right
        isInterrupted = sample.otherModifierDown
    }

    private mutating func continueGesture(
        with sample: SystemKeyboardSample,
        after previous: SystemKeyboardSample
    ) {
        if sample.otherModifierDown
            || (sample.leftShiftDown && sample.rightShiftDown)
            || sample.leftShiftDown != previous.leftShiftDown
            || sample.rightShiftDown != previous.rightShiftDown {
            isInterrupted = true
        }
    }

    private func completedTap(at sample: SystemKeyboardSample) -> SystemShiftTap? {
        guard let candidate,
              !isInterrupted,
              !sample.otherModifierDown,
              let baseline else {
            return nil
        }

        // Exactly the Shift press and its release may have changed modifiers.
        let expectedFlagsChanged: UInt32 = 2
        guard sample.keyDownCount &- baseline.keyDownCount == 0,
              sample.mouseDownCount &- baseline.mouseDownCount == 0,
              sample.flagsChangedCount &- baseline.flagsChangedCount
                == expectedFlagsChanged else {
            return nil
        }

        // With no other modifier change since the press, the latest one is
        // this Shift release.
        return SystemShiftTap(
            side: candidate,
            pressTime: baseline.pressTime,
            releaseTime: sample.lastModifierChangeTime
        )
    }

    private mutating func clearGesture() {
        candidate = nil
        isInterrupted = false
        baseline = nil
    }
}
