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

    func testOneCommittedSelectionMovesCharacterToFirst() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let learning = LearningSpy()
        learning.recordsByPronunciation["ㄐㄧㄢˋ"] = [
            "鍵": CharacterLearningRecord(
                character: "鍵",
                pronunciation: "ㄐㄧㄢˋ",
                selectionCount: 1,
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
        XCTAssertEqual(candidates.first?.userFrequency, 1)
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

    func testProviderMergesLongestFirstExactPhraseQueriesAheadOfCharacters() throws {
        let learning = LearningSpy()
        let longReadings = ["ㄐㄧㄡˇ", "ㄎㄨㄥ", "ㄕㄨ", "ㄖㄨˋ"]
        let shortReadings = ["ㄕㄨ", "ㄖㄨˋ"]
        learning.phraseRecordsByPronunciation[longReadings] = [
            makePhraseRecord(
                id: 10,
                phrase: "久空輸入",
                readings: longReadings
            ),
        ]
        learning.phraseRecordsByPronunciation[shortReadings] = [
            makePhraseRecord(
                id: 20,
                phrase: "輸入",
                readings: shortReadings
            ),
        ]
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning
        )

        let candidates = try provider.candidates(
            for: "ㄖㄨˋ",
            phraseQueries: [
                makePhraseQuery(longReadings),
                makePhraseQuery(shortReadings),
            ]
        )

        XCTAssertEqual(Array(candidates.prefix(2).map(\.text)), ["久空輸入", "輸入"])
        XCTAssertEqual(Array(candidates.prefix(2).map(\.type)), [.phrase, .phrase])
        XCTAssertEqual(candidates.first?.baseFrequency, 0)
        XCTAssertEqual(
            learning.requestedPhraseReadings,
            [longReadings, shortReadings]
        )
        XCTAssertTrue(candidates.dropFirst(2).contains { $0.type == .character })
    }

    func testFirstPartyPhraseReplacesWrongAutomaticCharacterForTest() throws {
        let provider = CharacterCandidateProvider(dictionary: try makeDictionary())
        var buffer = CompositionBuffer()
        XCTAssertTrue(
            buffer.acceptCandidate(
                Candidate(text: "冊", pronunciation: "ㄘㄜˋ"),
                reason: .implicitPassThrough
            )
        )

        let candidates = try provider.candidates(
            for: "ㄕˋ",
            phraseQueries: buffer.phraseLookupQueries(appending: "ㄕˋ")
        )

        let preferred = try XCTUnwrap(candidates.first)
        XCTAssertEqual(preferred.text, "測試")
        XCTAssertEqual(preferred.type, .phrase)
        XCTAssertEqual(preferred.pronunciationSequence, ["ㄘㄜˋ", "ㄕˋ"])
        XCTAssertTrue(
            buffer.acceptCandidate(preferred, reason: .returnKey)
        )
        XCTAssertEqual(buffer.text, "測試")
    }

    func testFirstPartySentenceReplacesEveryProvisionalCharacter() throws {
        let provider = CharacterCandidateProvider(dictionary: try makeDictionary())
        var buffer = CompositionBuffer()
        for (text, reading) in [
            ("冊", "ㄘㄜˋ"),
            ("士", "ㄕˋ"),
            ("中", "ㄓㄨㄥ"),
            ("頃", "ㄑㄧㄥˇ"),
            ("梢", "ㄕㄠ"),
        ] {
            XCTAssertTrue(
                buffer.acceptCandidate(
                    Candidate(text: text, pronunciation: reading),
                    reason: .implicitPassThrough
                )
            )
        }

        let candidates = try provider.candidates(
            for: "ㄏㄡˋ",
            phraseQueries: buffer.phraseLookupQueries(appending: "ㄏㄡˋ")
        )

        let preferred = try XCTUnwrap(candidates.first)
        XCTAssertEqual(preferred.text, "測試中請稍後")
        XCTAssertEqual(preferred.type, .phrase)
        XCTAssertTrue(buffer.acceptCandidate(preferred, reason: .returnKey))
        XCTAssertEqual(buffer.text, "測試中請稍後")
    }

    func testFirstPartyPhrasesRemainLongestSuffixFirst() throws {
        let provider = CharacterCandidateProvider(dictionary: try makeDictionary())
        let longReadings = ["ㄈㄢˊ", "ㄊㄧˇ", "ㄓㄨㄥ", "ㄨㄣˊ"]
        let shortReadings = ["ㄓㄨㄥ", "ㄨㄣˊ"]

        let candidates = try provider.candidates(
            for: "ㄨㄣˊ",
            phraseQueries: [
                makePhraseQuery(longReadings),
                makePhraseQuery(shortReadings),
            ]
        )

        XCTAssertEqual(
            Array(candidates.filter { $0.type == .phrase }.prefix(2).map(\.text)),
            ["繁體中文", "中文"]
        )
    }

    func testProviderRejectsWrongFinalReadingAndDeduplicatesQueries() throws {
        let learning = LearningSpy()
        let exactReadings = ["ㄕㄨ", "ㄖㄨˋ"]
        learning.phraseRecordsByPronunciation[exactReadings] = [
            makePhraseRecord(id: 1, phrase: "輸入", readings: exactReadings),
        ]
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning
        )

        let candidates = try provider.candidates(
            for: "ㄖㄨˋ",
            phraseQueries: [
                makePhraseQuery(["ㄕㄨ", "ㄔㄨ"]),
                makePhraseQuery(exactReadings),
                makePhraseQuery(exactReadings),
            ]
        )

        XCTAssertEqual(
            candidates.filter { $0.type == .phrase }.map(\.text),
            ["輸入"]
        )
        XCTAssertEqual(learning.requestedPhraseReadings, [exactReadings])
    }

    func testAddUserPhraseUsesInjectedClockAndRejectsMalformedPhrase() throws {
        let learning = LearningSpy()
        let date = Date(timeIntervalSince1970: 123)
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning,
            now: { date }
        )

        XCTAssertTrue(
            provider.addUserPhrase(
                phrase: "久空",
                pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
            )
        )
        XCTAssertFalse(
            provider.addUserPhrase(
                phrase: "錯誤",
                pronunciationSequence: ["ASCII", "ㄨˋ"]
            )
        )
        XCTAssertEqual(learning.addedPhrases.count, 1)
        XCTAssertEqual(learning.addedPhrases.first?.phrase, "久空")
        XCTAssertEqual(
            learning.addedPhrases.first?.readings,
            ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )
        XCTAssertEqual(learning.addedPhrases.first?.date, date)
    }

    func testRecordCommittedSelectionRecordsPhraseCandidate() throws {
        let learning = LearningSpy()
        let date = Date(timeIntervalSince1970: 456)
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning,
            now: { date }
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
        XCTAssertEqual(learning.addedPhrases.count, 1)
        XCTAssertEqual(learning.addedPhrases.first?.phrase, "久空")
        XCTAssertEqual(
            learning.addedPhrases.first?.readings,
            ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )
        XCTAssertEqual(learning.addedPhrases.first?.date, date)
        XCTAssertEqual(learning.recordedPhraseSelections.count, 1)
        XCTAssertEqual(learning.recordedPhraseSelections.first?.phrase, "久空")
        XCTAssertEqual(
            learning.recordedPhraseSelections.first?.readings,
            ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )
        XCTAssertEqual(learning.recordedPhraseSelections.first?.date, date)
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

    func testDisabledAutomaticLearningStopsCharacterAndPhraseCounting() throws {
        let learning = LearningSpy()
        var enabled = true
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning,
            isAutomaticLearningEnabled: { enabled }
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

        enabled = false
        for reason in reasons {
            provider.recordCommittedSelection(
                Candidate(text: "我", pronunciation: "ㄨㄛˇ"),
                reason: reason
            )
            provider.recordCommittedSelection(
                Candidate(
                    text: "久空",
                    pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                    type: .phrase
                ),
                reason: reason
            )
        }

        XCTAssertEqual(learning.recordedSelections, [])
        XCTAssertEqual(learning.recordedPhraseSelections, [])

        enabled = true
        provider.recordCommittedSelection(
            Candidate(text: "我", pronunciation: "ㄨㄛˇ"),
            reason: .space
        )

        XCTAssertEqual(
            learning.recordedSelections,
            [Selection(character: "我", pronunciation: "ㄨㄛˇ")]
        )
    }

    func testDisabledAutomaticLearningStillRanksAndAcceptsExplicitPhrases() throws {
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
            isAutomaticLearningEnabled: { false },
            now: { now }
        )

        let candidates = try provider.candidates(for: "ㄐㄧㄢˋ")

        XCTAssertEqual(candidates.first?.text, "鍵")
        XCTAssertTrue(
            provider.addUserPhrase(
                phrase: "久空",
                pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
            )
        )
        XCTAssertEqual(learning.addedPhrases.count, 1)
    }

    private struct Selection: Equatable {
        let character: String
        let pronunciation: String
    }

    private struct PhraseOperation: Equatable {
        let phrase: String
        let readings: [String]
        let date: Date
    }

    private final class LearningSpy: UserLearningProviding {
        var recordsByPronunciation: [String: [String: CharacterLearningRecord]] = [:]
        var phraseRecordsByPronunciation: [[String]: [UserPhraseRecord]] = [:]
        var recordedSelections: [Selection] = []
        var requestedPhraseReadings: [[String]] = []
        var addedPhrases: [PhraseOperation] = []
        var recordedPhraseSelections: [PhraseOperation] = []

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

        func phraseRecords(
            for pronunciationSequence: [String]
        ) -> [UserPhraseRecord] {
            requestedPhraseReadings.append(pronunciationSequence)
            return phraseRecordsByPronunciation[pronunciationSequence] ?? []
        }

        func addPhrase(
            phrase: String,
            pronunciationSequence: [String],
            createdAt: Date
        ) -> Bool {
            addedPhrases.append(
                PhraseOperation(
                    phrase: phrase,
                    readings: pronunciationSequence,
                    date: createdAt
                )
            )
            return true
        }

        func recordPhraseSelection(
            phrase: String,
            pronunciationSequence: [String],
            at date: Date
        ) {
            recordedPhraseSelections.append(
                PhraseOperation(
                    phrase: phrase,
                    readings: pronunciationSequence,
                    date: date
                )
            )
        }
    }

    private func makePhraseRecord(
        id: Int64,
        phrase: String,
        readings: [String],
        selectionCount: Int64 = 0,
        lastUsedAt: Date? = nil,
        pinned: Bool = false
    ) -> UserPhraseRecord {
        UserPhraseRecord(
            phraseID: id,
            phrase: phrase,
            pronunciationSequence: readings,
            createdAt: Date(timeIntervalSince1970: TimeInterval(id)),
            lastUsedAt: lastUsedAt,
            selectionCount: selectionCount,
            pinned: pinned
        )
    }

    private func makePhraseQuery(
        _ readings: [String]
    ) -> CompositionPhraseQuery {
        CompositionPhraseQuery(
            pronunciationSequence: readings,
            existingSuffixUnitIDs: Array(
                repeating: UUID(),
                count: max(0, readings.count - 1)
            )
        )
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
