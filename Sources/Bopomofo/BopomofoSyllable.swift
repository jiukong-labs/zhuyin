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
