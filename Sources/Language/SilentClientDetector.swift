import Foundation

/// Notices a client that stopped routing key events to the input method right
/// after a switch to Chinese.
///
/// Some observed client sessions stop delivering keys after switching from
/// English to Chinese, despite the selected source already being Chinese.
/// The detector watches only that transition and plain keys; the caller also
/// validates focus and source before attempting recovery. Plain keys alone
/// cannot prove that the focused control is editable, so attempts are bounded.
struct SilentClientDetector {
    /// How long a plain key may go unseen before the client counts as silent.
    /// A delivered key normally arrives within a few milliseconds; this also
    /// absorbs a main thread that was briefly busy switching sources.
    static let deliveryGrace: TimeInterval = 0.2
    /// A switch is watched until the client proves itself or this passes.
    static let watchDuration: TimeInterval = 30
    /// Re-attaching cannot help a client that is not editing text at all, so
    /// the detector gives up after this many attempts for one switch.
    static let maximumAttempts = 2

    private var watchStart: TimeInterval?
    private var keyWindowStart: TimeInterval?
    /// The first plain key typed since the key window opened. While the watch
    /// lasts, no key typed since then has reached the input method, so this
    /// one has waited longest; later keys must not postpone the decision.
    private(set) var firstUndeliveredKey: TimeInterval?
    private var attempts = 0
    private(set) var isReattaching = false

    var isWatching: Bool {
        watchStart != nil
    }

    /// The input method just switched the client to Chinese.
    mutating func switchedToChinese(at time: TimeInterval) {
        watchStart = time
        keyWindowStart = time
        firstUndeliveredKey = nil
        attempts = 0
        isReattaching = false
    }

    /// Only a key typed after Chinese resumed proves the Chinese route works.
    /// Keys delivered during the temporary English source, or delayed from
    /// before the return to Chinese, cannot end the recovery watch.
    mutating func clientDeliveredKeyDown(
        at time: TimeInterval,
        mode: LanguageMode?
    ) {
        guard mode == .chinese,
              !isReattaching,
              let keyWindowStart,
              time >= keyWindowStart else {
            return
        }
        stopWatching()
    }

    /// The temporary English source has returned to Chinese. Keep the
    /// original deadline and attempt count, and judge only newly typed keys.
    mutating func reattachedToChinese(at time: TimeInterval) {
        guard isReattaching, let watchStart else {
            return
        }
        guard time - watchStart <= Self.watchDuration else {
            stopWatching()
            return
        }
        keyWindowStart = time
        firstUndeliveredKey = nil
        isReattaching = false
    }

    /// Focus moved, the mode left Chinese, or the input method was deselected.
    mutating func stopWatching() {
        watchStart = nil
        keyWindowStart = nil
        firstUndeliveredKey = nil
        attempts = 0
        isReattaching = false
    }

    /// Returns true when the client should be re-attached now.
    ///
    /// `lastPlainKeyDown` is the hardware time of the most recent key-down
    /// typed without Command or Control, or nil when there has been none.
    /// Continuous typing leaves no pause after that latest key, so the
    /// detector judges the first key it saw in the window instead.
    mutating func shouldReattach(
        now: TimeInterval,
        lastPlainKeyDown: TimeInterval?
    ) -> Bool {
        guard let watchStart else {
            return false
        }
        guard now - watchStart <= Self.watchDuration else {
            stopWatching()
            return false
        }
        guard !isReattaching, let keyWindowStart else {
            return false
        }
        if firstUndeliveredKey == nil,
           let key = lastPlainKeyDown,
           key > keyWindowStart {
            firstUndeliveredKey = key
        }
        guard let key = firstUndeliveredKey,
              now - key >= Self.deliveryGrace else {
            return false
        }
        guard attempts < Self.maximumAttempts else {
            stopWatching()
            return false
        }

        attempts += 1
        // Source changes are asynchronous. Suspend decisions until the
        // caller confirms that the Chinese source has actually returned.
        self.keyWindowStart = nil
        isReattaching = true
        return true
    }
}

/// Allows only the current recovery callback to restore Chinese, while its
/// temporary English source and client are still selected.
struct ClientReattachmentGuard {
    private var pendingToken: UUID?

    var isPending: Bool {
        pendingToken != nil
    }

    func contains(_ token: UUID) -> Bool {
        pendingToken == token
    }

    mutating func begin() -> UUID {
        let token = UUID()
        pendingToken = token
        return token
    }

    mutating func cancel() {
        pendingToken = nil
    }

    mutating func claim(
        token: UUID,
        currentMode: LanguageMode?,
        isCurrentClient: Bool
    ) -> Bool {
        guard pendingToken == token else {
            return false
        }
        // Consume only this callback's token. An older callback must never
        // cancel or complete a recovery that started after it.
        pendingToken = nil
        return currentMode == .english && isCurrentClient
    }
}

/// Decides which keys to hold while a recovery has the client on its
/// temporary English source. A client that hands keys over then works again,
/// but its user was typing Chinese; only keys that would type text are held
/// for replay, so editing and navigation keys keep their meaning.
enum ReattachmentKeyHold {
    static func holds(characters: String?, hasCommandModifier: Bool) -> Bool {
        guard !hasCommandModifier,
              let characters,
              !characters.isEmpty else {
            return false
        }
        // Return, Tab, Delete and Escape are control characters; arrows and
        // function keys use the private range AppKit reserves for them.
        return characters.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
                && !(0xF700...0xF8FF).contains($0.value)
        }
    }
}
