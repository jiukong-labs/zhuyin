enum CompositionTextAction: Equatable {
    case none
    case updateMarkedText(String)
    case clearMarkedText
    case completeSyllable(BopomofoSyllable)
    case commitText(String)
}

struct InputSessionResult: Equatable {
    let textAction: CompositionTextAction
    let handled: Bool

    static let passThrough = InputSessionResult(textAction: .none, handled: false)
}

struct BopomofoInputSession {
    private let keyboardLayout: any KeyboardLayout
    private var parser = BopomofoParser()

    init(keyboardLayout: any KeyboardLayout = StandardZhuyinLayout()) {
        self.keyboardLayout = keyboardLayout
    }

    var hasComposition: Bool {
        parser.hasComposition
    }

    var markedText: String? {
        guard hasComposition else {
            return nil
        }

        return parser.syllable.text
    }

    mutating func handle(_ key: KeyboardKey) -> InputSessionResult {
        if let component = keyboardLayout.component(for: key) {
            return handle(component)
        }

        switch key {
        case .deleteBackward:
            return deleteBackward()
        case .escape:
            return discardComposition()
        case .returnKey, .keypadEnter:
            return commitComposition(handled: true)
        default:
            return finishBeforePassThrough()
        }
    }

    mutating func finishBeforePassThrough() -> InputSessionResult {
        commitComposition(handled: false)
    }

    mutating func commitComposition() -> InputSessionResult {
        commitComposition(handled: true)
    }

    mutating func discardComposition() -> InputSessionResult {
        guard parser.discardCurrentSyllable() else {
            return .passThrough
        }

        return InputSessionResult(textAction: .clearMarkedText, handled: true)
    }

    private mutating func handle(_ component: BopomofoComponent) -> InputSessionResult {
        switch parser.input(component) {
        case .rejected:
            return .passThrough
        case let .composing(syllable):
            return InputSessionResult(
                textAction: .updateMarkedText(syllable.text),
                handled: true
            )
        case let .completed(syllable):
            return InputSessionResult(
                textAction: .completeSyllable(syllable),
                handled: true
            )
        }
    }

    private mutating func deleteBackward() -> InputSessionResult {
        guard let syllable = parser.deleteBackward() else {
            return .passThrough
        }

        let action: CompositionTextAction = syllable.isEmpty
            ? .clearMarkedText
            : .updateMarkedText(syllable.text)
        return InputSessionResult(textAction: action, handled: true)
    }

    private mutating func commitComposition(handled: Bool) -> InputSessionResult {
        guard let syllable = parser.takeCurrentSyllable() else {
            return .passThrough
        }

        return InputSessionResult(
            textAction: .commitText(syllable.text),
            handled: handled
        )
    }
}
