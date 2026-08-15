import Foundation
import XCTest

final class CandidateRankerTests: XCTestCase {
    private let ranker = CandidateRanker()
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testUnlearnedCandidatesPreserveBaseRank() {
        let candidates = [
            makeCandidate("第三", baseRank: 2, sourceOrder: 30),
            makeCandidate("第一", baseRank: 0, sourceOrder: 10),
            makeCandidate("第二", baseRank: 1, sourceOrder: 20),
        ]

        XCTAssertEqual(
            ranker.ranked(candidates, at: now).map(\.text),
            ["第一", "第二", "第三"]
        )
    }

    func testRepeatedSelectionRaisesCandidateGradually() throws {
        let expectedPositions = [23, 12, 7, 4, 1]

        for (selectionCount, expectedPosition) in expectedPositions.enumerated() {
            var candidates = (0 ..< 22).map { baseRank in
                makeCandidate("字\(baseRank)", baseRank: baseRank)
            }
            candidates.append(
                makeCandidate(
                    "鍵",
                    baseRank: 22,
                    userFrequency: Int64(selectionCount),
                    lastUsed: selectionCount == 0 ? nil : now
                )
            )

            let ranked = ranker.ranked(candidates, at: now)
            let actualIndex = try XCTUnwrap(
                ranked.firstIndex(where: { $0.text == "鍵" })
            )
            XCTAssertEqual(
                actualIndex + 1,
                expectedPosition,
                "Unexpected position after \(selectionCount) selections"
            )
        }
    }

    func testUserFrequencyUsesLogarithmicBonus() {
        let candidate = makeCandidate(
            "鍵",
            baseRank: 3,
            userFrequency: 3
        )

        XCTAssertEqual(
            ranker.score(for: candidate, at: now),
            13,
            accuracy: 0.000_001
        )
    }

    func testRecencyBonusHasSevenDayHalfLife() {
        let justUsed = makeCandidate(
            "今",
            baseRank: 10,
            lastUsed: now
        )
        let usedOneHalfLifeAgo = makeCandidate(
            "週",
            baseRank: 10,
            lastUsed: now.addingTimeInterval(
                -CandidateRanker.defaultRecencyHalfLife
            )
        )

        XCTAssertEqual(
            ranker.score(for: justUsed, at: now),
            -6,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ranker.score(for: usedOneHalfLifeAgo, at: now),
            -8,
            accuracy: 0.000_001
        )
    }

    func testFutureTimestampIsClampedToFreshestRecency() {
        let candidate = makeCandidate(
            "未",
            baseRank: 10,
            lastUsed: now.addingTimeInterval(60 * 60)
        )

        XCTAssertEqual(
            ranker.score(for: candidate, at: now),
            -6,
            accuracy: 0.000_001
        )
    }

    func testPinnedCandidateAlwaysOccupiesHighestTier() {
        let heavilyLearned = makeCandidate(
            "常",
            baseRank: 0,
            userFrequency: 10_000,
            lastUsed: now
        )
        let pinned = makeCandidate(
            "釘",
            baseRank: 999,
            pinned: true
        )

        XCTAssertEqual(
            ranker.ranked([heavilyLearned, pinned], at: now).map(\.text),
            ["釘", "常"]
        )
    }

    func testFixedPhraseBonusDominatesMaximumCharacterLearning() {
        let maximumLearnedCharacter = Candidate(
            text: "字",
            pronunciation: "ㄗˋ",
            userFrequency: Int64.max,
            lastUsed: now
        )
        let exactPhrase = Candidate(
            text: "造詞",
            pronunciationSequence: ["ㄗㄠˋ", "ㄘˊ"],
            type: .phrase,
            baseRank: 9_999,
            baseFrequency: 0
        )

        XCTAssertEqual(
            ranker.score(for: exactPhrase, at: now),
            CandidateRanker.defaultPhraseBonus,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ranker.ranked(
                [maximumLearnedCharacter, exactPhrase],
                at: now
            ).map(\.text),
            ["造詞", "字"]
        )
    }

    func testPinnedCharacterStillOutranksPhraseBonus() {
        let pinnedCharacter = Candidate(
            text: "釘",
            pronunciation: "ㄉㄧㄥ",
            baseRank: 999,
            pinned: true
        )
        let exactPhrase = Candidate(
            text: "造詞",
            pronunciationSequence: ["ㄗㄠˋ", "ㄘˊ"],
            type: .phrase,
            baseFrequency: 0,
            userFrequency: Int64.max,
            lastUsed: now
        )

        XCTAssertEqual(
            ranker.ranked([exactPhrase, pinnedCharacter], at: now)
                .map(\.text),
            ["釘", "造詞"]
        )
    }

    func testBaseFrequencyOverridesRankWhenAvailable() {
        let frequencyCandidate = Candidate(
            text: "頻",
            pronunciation: "ㄆㄧㄣˊ",
            baseRank: 10,
            baseFrequency: 2
        )
        let rankCandidate = makeCandidate("序", baseRank: 0)

        XCTAssertEqual(
            ranker.ranked([rankCandidate, frequencyCandidate], at: now)
                .map(\.text),
            ["頻", "序"]
        )
    }

    func testTiesUseBaseRankSourceOrderAndTextDeterministically() {
        let candidates = [
            makeCandidate("乙", baseRank: 1, sourceOrder: 20),
            makeCandidate("甲", baseRank: 1, sourceOrder: 20),
            makeCandidate("丙", baseRank: 1, sourceOrder: 10),
            makeCandidate("首", baseRank: 0, sourceOrder: 100),
        ]

        XCTAssertEqual(
            ranker.ranked(candidates, at: now).map(\.text),
            ["首", "丙", "乙", "甲"]
        )
    }

    func testCandidateIdentityIncludesReadingAndType() {
        let character = Candidate(
            text: "行",
            pronunciation: "ㄒㄧㄥˊ"
        )
        let otherReading = Candidate(
            text: "行",
            pronunciation: "ㄏㄤˊ"
        )
        let phrase = Candidate(
            text: "行",
            pronunciationSequence: ["ㄒㄧㄥˊ"],
            type: .phrase
        )

        XCTAssertNotEqual(character.id, otherReading.id)
        XCTAssertNotEqual(character.id, phrase.id)
        XCTAssertEqual(phrase.pronunciationSequence, ["ㄒㄧㄥˊ"])
        XCTAssertEqual(phrase.pronunciation, "ㄒㄧㄥˊ")
    }

    private func makeCandidate(
        _ text: String,
        baseRank: Int,
        sourceOrder: Int64 = 0,
        userFrequency: Int64 = 0,
        lastUsed: Date? = nil,
        pinned: Bool = false
    ) -> Candidate {
        Candidate(
            text: text,
            pronunciation: "ㄘㄜˋ",
            baseRank: baseRank,
            sourceOrder: sourceOrder,
            userFrequency: userFrequency,
            lastUsed: lastUsed,
            pinned: pinned
        )
    }
}
