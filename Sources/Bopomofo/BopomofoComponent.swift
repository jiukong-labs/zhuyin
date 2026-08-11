enum BopomofoInitial: String, CaseIterable {
    case b = "ㄅ"
    case p = "ㄆ"
    case m = "ㄇ"
    case f = "ㄈ"
    case d = "ㄉ"
    case t = "ㄊ"
    case n = "ㄋ"
    case l = "ㄌ"
    case g = "ㄍ"
    case k = "ㄎ"
    case h = "ㄏ"
    case j = "ㄐ"
    case q = "ㄑ"
    case x = "ㄒ"
    case zh = "ㄓ"
    case ch = "ㄔ"
    case sh = "ㄕ"
    case r = "ㄖ"
    case z = "ㄗ"
    case c = "ㄘ"
    case s = "ㄙ"
}

enum BopomofoMedial: String, CaseIterable {
    case i = "ㄧ"
    case u = "ㄨ"
    case yu = "ㄩ"
}

enum BopomofoFinal: String, CaseIterable {
    case a = "ㄚ"
    case o = "ㄛ"
    case e = "ㄜ"
    case eh = "ㄝ"
    case ai = "ㄞ"
    case ei = "ㄟ"
    case ao = "ㄠ"
    case ou = "ㄡ"
    case an = "ㄢ"
    case en = "ㄣ"
    case ang = "ㄤ"
    case eng = "ㄥ"
    case er = "ㄦ"
}

enum BopomofoTone: String, CaseIterable {
    case first = ""
    case second = "ˊ"
    case third = "ˇ"
    case fourth = "ˋ"
    case neutral = "˙"
}

enum BopomofoComponent: Equatable {
    case initial(BopomofoInitial)
    case medial(BopomofoMedial)
    case final(BopomofoFinal)
    case tone(BopomofoTone)

    var text: String {
        switch self {
        case let .initial(initial):
            return initial.rawValue
        case let .medial(medial):
            return medial.rawValue
        case let .final(final):
            return final.rawValue
        case let .tone(tone):
            return tone.rawValue
        }
    }
}
