enum BopomofoParserResult: Equatable {
    case rejected
    case composing(BopomofoSyllable)
    case completed(BopomofoSyllable)
}

struct BopomofoParser {
    private(set) var syllable = BopomofoSyllable()

    var hasComposition: Bool {
        !syllable.isEmpty
    }

    mutating func input(_ component: BopomofoComponent) -> BopomofoParserResult {
        if case .tone = component {
            guard hasComposition else {
                return .rejected
            }

            syllable.apply(component)
            let completedSyllable = syllable
            syllable = BopomofoSyllable()
            return .completed(completedSyllable)
        }

        syllable.apply(component)
        return .composing(syllable)
    }

    mutating func deleteBackward() -> BopomofoSyllable? {
        guard syllable.removeLastComponent() else {
            return nil
        }

        return syllable
    }

    mutating func takeCurrentSyllable() -> BopomofoSyllable? {
        guard hasComposition else {
            return nil
        }

        let currentSyllable = syllable
        syllable = BopomofoSyllable()
        return currentSyllable
    }

    @discardableResult
    mutating func discardCurrentSyllable() -> Bool {
        guard hasComposition else {
            return false
        }

        syllable = BopomofoSyllable()
        return true
    }
}
