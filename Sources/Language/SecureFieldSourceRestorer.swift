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
/// typing into the app holding it, such as under Terminal's Secure Keyboard
/// Entry, was the user's.
///
/// Chrome can keep secure input on after the user has moved to another app,
/// so the password field also counts as ended once an app other than the
/// one holding it is in front.
struct SecureFieldSourceRestorer {
    /// How long after the switch secure input may still turn on for the
    /// switch to count as the password field's.
    static let confirmationWindow: TimeInterval = 0.5
    /// Gives macOS the first chance to restore the source itself, and lets
    /// focus move between two password fields without a restore in between.
    static let restoreDelay: TimeInterval = 0.3
    /// Secure input left on this long is no longer a password being typed.
    static let maximumWait: TimeInterval = 600

    /// Secure event input and the frontmost app at one moment.
    struct SecureInput: Equatable {
        static let off = SecureInput(enabled: false, holderPID: nil, frontmostPID: nil)

        /// Whether any process has secure event input on.
        var enabled: Bool
        /// The app holding secure input, when macOS reports it.
        var holderPID: pid_t?
        /// The frontmost app, when known.
        var frontmostPID: pid_t?

        /// Secure input is on in the app in front, which is where a password
        /// field or Secure Keyboard Entry the user is typing into lives. An
        /// unknown holder or front app counts as that app.
        var heldByFrontmostApp: Bool {
            guard enabled else {
                return false
            }
            guard let holderPID, let frontmostPID else {
                return true
            }
            return holderPID == frontmostPID
        }
    }

    enum Outcome: Equatable {
        /// Still waiting, or nothing to do.
        case none
        /// Select this Jiukong mode again.
        case restore(LanguageMode)
        /// Secure input never started; the user chose that source.
        case dismissed
        /// Secure input was already on in the app Jiukong was typing into,
        /// so the switch was the user's.
        case notWatched
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
        /// The app that held secure input while it was in front.
        var fieldAppPID: pid_t?
        var fieldEndedAt: TimeInterval?

        mutating func noteFieldApp(_ secureInput: SecureInput) {
            guard fieldAppPID == nil,
                  secureInput.enabled,
                  let holderPID = secureInput.holderPID,
                  holderPID == secureInput.frontmostPID else {
                return
            }
            fieldAppPID = holderPID
        }

        func fieldHasEnded(_ secureInput: SecureInput) -> Bool {
            guard secureInput.enabled else {
                return true
            }
            // The holder in front again, as a locked screen's loginwindow
            // is, keeps the field going.
            guard let fieldAppPID,
                  let frontmostPID = secureInput.frontmostPID,
                  frontmostPID != secureInput.holderPID else {
                return false
            }
            return frontmostPID != fieldAppPID
        }
    }

    private var selectedMode: LanguageMode?
    private var secureInputWhileTyping = false
    private var displacement: Displacement?

    var isWaiting: Bool {
        displacement != nil
    }

    init(selectedMode: LanguageMode?) {
        self.selectedMode = selectedMode
    }

    /// Samples secure input as a key reaches Jiukong, before any password
    /// field could have taken over.
    mutating func noteJiukongTyping(_ secureInput: SecureInput) {
        secureInputWhileTyping = secureInput.heldByFrontmostApp
    }

    /// A Jiukong controller activated. A Chrome page whose password field
    /// already has focus activates Jiukong just after turning secure input
    /// on and just before macOS selects ABC, so an activation only ever
    /// clears the sample.
    mutating func noteJiukongActivated(_ secureInput: SecureInput) {
        if !secureInput.heldByFrontmostApp {
            secureInputWhileTyping = false
        }
    }

    /// `mode` is nil for a source other than Jiukong.
    mutating func sourceChanged(
        to mode: LanguageMode?,
        sourceID: String?,
        secureInput: SecureInput,
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
        guard let previous else {
            return .none
        }
        guard !secureInputWhileTyping else {
            return .notWatched
        }
        var displacement = Displacement(
            mode: previous,
            sourceID: sourceID,
            startedAt: now,
            confirmed: secureInput.enabled
        )
        displacement.noteFieldApp(secureInput)
        self.displacement = displacement
        return .none
    }

    mutating func poll(
        secureInput: SecureInput,
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
            guard secureInput.enabled else {
                if now - displacement.startedAt > Self.confirmationWindow {
                    return endWaiting(.dismissed)
                }
                return .none
            }
            displacement.confirmed = true
        }
        // The front app can lag the switch by a moment, so the field's app
        // is taken from the first poll that sees it in front.
        displacement.noteFieldApp(secureInput)
        if now - displacement.startedAt > Self.maximumWait {
            return endWaiting(.gaveUp)
        }
        guard displacement.fieldHasEnded(secureInput) else {
            displacement.fieldEndedAt = nil
            self.displacement = displacement
            return .none
        }
        let endedAt = displacement.fieldEndedAt ?? now
        guard now - endedAt >= Self.restoreDelay else {
            displacement.fieldEndedAt = endedAt
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
