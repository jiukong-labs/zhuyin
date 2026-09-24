import Foundation

/// Brings Jiukong back after a password field made macOS switch to an
/// ASCII-capable source such as ABC.
///
/// A password field turns on secure event input and allows only
/// ASCII-capable input sources, so macOS selects one. macOS restores the
/// previous source after its own password prompts, but a Chrome password
/// field that lost focus to Outlook left Outlook on ABC until the user chose
/// Jiukong again. Only a switch that coincided with secure input starting is
/// undone: a switch made while secure input was already on while Jiukong was
/// in use, such as under Terminal's Secure Keyboard Entry, was the user's.
struct SecureFieldSourceRestorer {
    /// How long after the switch secure input may still turn on for the
    /// switch to count as the password field's.
    static let confirmationWindow: TimeInterval = 0.5
    /// Gives macOS the first chance to restore the source itself, and lets
    /// focus move between two password fields without a restore in between.
    static let restoreDelay: TimeInterval = 0.3
    /// Secure input left on this long is no longer a password being typed.
    static let maximumWait: TimeInterval = 600

    enum Outcome: Equatable {
        /// Still waiting, or nothing to do.
        case none
        /// Select this Jiukong mode again.
        case restore(LanguageMode)
        /// Secure input never started; the user chose that source.
        case dismissed
        /// The source changed to something else; leave it.
        case superseded
        /// Secure input stayed on too long.
        case gaveUp
    }

    private struct Displacement {
        var mode: LanguageMode
        var sourceID: String?
        var startedAt: TimeInterval
        var confirmed: Bool
        var secureInputEndedAt: TimeInterval?
    }

    private var selectedMode: LanguageMode?
    private var secureInputWhileInUse = false
    private var displacement: Displacement?

    var isWaiting: Bool {
        displacement != nil
    }

    init(selectedMode: LanguageMode?) {
        self.selectedMode = selectedMode
    }

    /// Samples secure input while a client is typing with Jiukong, before
    /// any password field could have taken over.
    mutating func noteJiukongInUse(secureInputEnabled: Bool) {
        secureInputWhileInUse = secureInputEnabled
    }

    /// `mode` is nil for a source other than Jiukong.
    mutating func sourceChanged(
        to mode: LanguageMode?,
        sourceID: String?,
        secureInputEnabled: Bool,
        at now: TimeInterval
    ) -> Outcome {
        let previous = selectedMode
        selectedMode = mode

        if mode != nil {
            return endWaiting(.superseded)
        }
        if let displacement {
            return displacement.sourceID == sourceID ? .none : endWaiting(.superseded)
        }
        guard let previous, !secureInputWhileInUse else {
            return .none
        }
        displacement = Displacement(
            mode: previous,
            sourceID: sourceID,
            startedAt: now,
            confirmed: secureInputEnabled
        )
        return .none
    }

    mutating func poll(
        secureInputEnabled: Bool,
        currentSourceID: String?,
        at now: TimeInterval
    ) -> Outcome {
        guard var displacement else {
            return .none
        }
        guard currentSourceID == displacement.sourceID else {
            return endWaiting(.superseded)
        }
        if !displacement.confirmed {
            guard secureInputEnabled else {
                if now - displacement.startedAt > Self.confirmationWindow {
                    return endWaiting(.dismissed)
                }
                return .none
            }
            displacement.confirmed = true
        }
        if now - displacement.startedAt > Self.maximumWait {
            return endWaiting(.gaveUp)
        }
        if secureInputEnabled {
            displacement.secureInputEndedAt = nil
            self.displacement = displacement
            return .none
        }
        let endedAt = displacement.secureInputEndedAt ?? now
        guard now - endedAt >= Self.restoreDelay else {
            displacement.secureInputEndedAt = endedAt
            self.displacement = displacement
            return .none
        }
        return endWaiting(.restore(displacement.mode))
    }

    private mutating func endWaiting(_ outcome: Outcome) -> Outcome {
        guard displacement != nil else {
            return .none
        }
        displacement = nil
        return outcome
    }
}
