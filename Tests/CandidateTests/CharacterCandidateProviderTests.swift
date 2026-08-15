import Foundation
import XCTest

final class CharacterCandidateProviderTests: XCTestCase {
    func testProviderWithoutLearningPreservesBundledDictionaryOrder() throws {
        let dictionary = try makeDictionary()
        let provider = CharacterCandidateProvider(dictionary: dictionary)

        let candidates = try provider.candidates(for: "ㄨㄛˇ")

        XCTAssertEqual(candidates.map(\.text), try dictionary.candidates(for: "ㄨㄛˇ"))
        XCTAssertEqual(candidates.first?.text, "我")
        XCTAssertTrue(candidates.allSatisfy { candidate in
            candidate.type == .character
                && candidate.baseFrequency == nil
                && candidate.userFrequency == 0
                && candidate.lastUsed == nil
                && !candidate.pinned
        })
    }

    func testLearningMetadataRaisesFrequentlySelectedCharacter() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let learning = LearningSpy()
        learning.recordsByPronunciation["ㄐㄧㄢˋ"] = [
            "鍵": CharacterLearningRecord(
                character: "鍵",
                pronunciation: "ㄐㄧㄢˋ",
                selectionCount: 4,
                lastSelectedAt: now,
                pinned: false
            ),
        ]
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning,
            now: { now }
        )

        let candidates = try provider.candidates(for: "ㄐㄧㄢˋ")

        XCTAssertEqual(candidates.first?.text, "鍵")
        XCTAssertEqual(candidates.first?.baseRank, 22)
        XCTAssertEqual(candidates.first?.sourceOrder, 6_101)
        XCTAssertEqual(candidates.first?.userFrequency, 4)
        XCTAssertEqual(candidates.first?.lastUsed, now)
    }

    func testPinnedLearningRecordOutranksOtherCandidates() throws {
        let learning = LearningSpy()
        learning.recordsByPronunciation["ㄨㄛˇ"] = [
            "婑": CharacterLearningRecord(
                character: "婑",
                pronunciation: "ㄨㄛˇ",
                selectionCount: 0,
                lastSelectedAt: nil,
                pinned: true
            ),
        ]
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning
        )

        XCTAssertEqual(
            try provider.candidates(for: "ㄨㄛˇ").first?.text,
            "婑"
        )
    }

    func testLearningRecordsForUnknownCharactersAreIgnored() throws {
        let learning = LearningSpy()
        learning.recordsByPronunciation["ㄨㄛˇ"] = [
            "不存在": CharacterLearningRecord(
                character: "不存在",
                pronunciation: "ㄨㄛˇ",
                selectionCount: 1_000,
                lastSelectedAt: Date(),
                pinned: true
            ),
        ]
        let dictionary = try makeDictionary()
        let provider = CharacterCandidateProvider(
            dictionary: dictionary,
            learning: learning
        )

        XCTAssertEqual(
            try provider.candidates(for: "ㄨㄛˇ").map(\.text),
            try dictionary.candidates(for: "ㄨㄛˇ")
        )
    }

    func testUnknownPronunciationReturnsNoCandidates() throws {
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary()
        )

        XCTAssertEqual(try provider.candidates(for: "not-zhuyin"), [])
    }

    func testEveryCommitReasonRecordsCharacterSelection() throws {
        let learning = LearningSpy()
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning
        )
        let candidate = Candidate(
            text: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )

        let reasons: [CandidateCommitReason] = [
            .space,
            .returnKey,
            .number(9),
            .mouse,
            .implicitPassThrough,
            .lifecycle,
            .clientHandoff,
        ]
        for reason in reasons {
            provider.recordCommittedSelection(candidate, reason: reason)
        }

        XCTAssertEqual(
            learning.recordedSelections,
            Array(
                repeating: Selection(
                    character: "鍵",
                    pronunciation: "ㄐㄧㄢˋ"
                ),
                count: reasons.count
            )
        )
    }

    func testRecordCommittedSelectionIgnoresPhraseCandidate() throws {
        let learning = LearningSpy()
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning
        )

        provider.recordCommittedSelection(
            Candidate(
                text: "久空",
                pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                type: .phrase
            ),
            reason: .returnKey
        )

        XCTAssertEqual(learning.recordedSelections, [])
    }

    func testRecordCommittedSelectionRejectsMalformedCharacterIdentity() throws {
        let learning = LearningSpy()
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning
        )
        let malformedCandidates = [
            Candidate(text: "", pronunciation: "ㄨㄛˇ"),
            Candidate(text: "我", pronunciation: ""),
            Candidate(
                text: "我",
                pronunciationSequence: ["ㄨㄛˇ", "ㄨㄛˋ"],
                type: .character
            ),
        ]

        for candidate in malformedCandidates {
            provider.recordCommittedSelection(candidate, reason: .space)
        }

        XCTAssertEqual(learning.recordedSelections, [])
    }

    private struct Selection: Equatable {
        let character: String
        let pronunciation: String
    }

    private final class LearningSpy: UserLearningProviding {
        var recordsByPronunciation: [String: [String: CharacterLearningRecord]] = [:]
        var recordedSelections: [Selection] = []

        func records(
            for pronunciation: String
        ) -> [String: CharacterLearningRecord] {
            recordsByPronunciation[pronunciation] ?? [:]
        }

        func recordSelection(character: String, pronunciation: String) {
            recordedSelections.append(
                Selection(
                    character: character,
                    pronunciation: pronunciation
                )
            )
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var databaseURL: URL {
        repositoryRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Dictionary", isDirectory: true)
            .appendingPathComponent("JiukongZhuyin.sqlite3")
    }

    private func makeDictionary() throws -> CharacterDictionary {
        try CharacterDictionary(databaseURL: databaseURL)
    }
}
