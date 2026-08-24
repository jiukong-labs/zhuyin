struct BopomofoSyllable: Equatable {
    private enum ComponentSlot: Equatable {
        case initial
        case medial
        case final
        case tone
    }

    private(set) var initial: BopomofoInitial?
    private(set) var medial: BopomofoMedial?
    private(set) var final: BopomofoFinal?
    private(set) var tone: BopomofoTone?
    private var inputOrder: [ComponentSlot] = []

    init() {}

    /// Reconstructs a completed syllable from the canonical pronunciation
    /// stored on a converted composition unit. An unmarked pronunciation is
    /// a completed first-tone syllable, so its invisible tone is restored as
    /// the final input component and is removed by the first Backspace.
    init?(pronunciation: String) {
        guard !pronunciation.isEmpty else {
            return nil
        }

        var symbols = pronunciation.map(String.init)
        let restoredTone: BopomofoTone
        if symbols.first == BopomofoTone.neutral.rawValue {
            restoredTone = .neutral
            symbols.removeFirst()
        } else if let last = symbols.last,
                  let explicitTone = BopomofoTone(rawValue: last),
                  explicitTone != .first {
            restoredTone = explicitTone
            symbols.removeLast()
        } else {
            restoredTone = .first
        }

        guard !symbols.isEmpty else {
            return nil
        }

        self.init()
        for symbol in symbols {
            if let initial = BopomofoInitial(rawValue: symbol) {
                guard self.initial == nil,
                      medial == nil,
                      final == nil else {
                    return nil
                }
                apply(.initial(initial))
            } else if let medial = BopomofoMedial(rawValue: symbol) {
                guard self.medial == nil,
                      final == nil else {
                    return nil
                }
                apply(.medial(medial))
            } else if let final = BopomofoFinal(rawValue: symbol) {
                guard self.final == nil else {
                    return nil
                }
                apply(.final(final))
            } else {
                return nil
            }
        }
        apply(.tone(restoredTone))

        guard text == pronunciation else {
            return nil
        }
    }

    var isEmpty: Bool {
        initial == nil && medial == nil && final == nil && tone == nil
    }

    var text: String {
        let body = [
            initial?.rawValue,
            medial?.rawValue,
            final?.rawValue
        ]
        .compactMap { $0 }
        .joined()

        guard let tone else {
            return body
        }

        if tone == .neutral {
            return tone.rawValue + body
        }

        return body + tone.rawValue
    }

    mutating func apply(_ component: BopomofoComponent) {
        let slot: ComponentSlot

        switch component {
        case let .initial(value):
            initial = value
            slot = .initial
        case let .medial(value):
            medial = value
            slot = .medial
        case let .final(value):
            final = value
            slot = .final
        case let .tone(value):
            tone = value
            slot = .tone
        }

        inputOrder.removeAll { $0 == slot }
        inputOrder.append(slot)
    }

    @discardableResult
    mutating func removeLastComponent() -> Bool {
        guard let slot = inputOrder.popLast() else {
            return false
        }

        switch slot {
        case .initial:
            initial = nil
        case .medial:
            medial = nil
        case .final:
            final = nil
        case .tone:
            tone = nil
        }

        return true
    }

    static func == (lhs: BopomofoSyllable, rhs: BopomofoSyllable) -> Bool {
        lhs.initial == rhs.initial
            && lhs.medial == rhs.medial
            && lhs.final == rhs.final
            && lhs.tone == rhs.tone
    }
}
