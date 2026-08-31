import Foundation
import XCTest

final class CharacterCandidateProviderTests: XCTestCase {
    func testProviderWithoutPersonalLearningUsesBuiltInDefaultRanking() throws {
        let dictionary = try makeDictionary()
        let provider = CharacterCandidateProvider(dictionary: dictionary)

        let candidates = try provider.candidates(for: "ㄨㄛˇ")

        // No personal learning history is needed for the captured first-party
        // default selection prior. Remaining ties use the MOE usage tier,
        // Jiukong phrase attestations, and finally CNS source order.
        let expectedOrder = try dictionary.candidateEntries(for: "ㄨㄛˇ")
            .filter(\.isInGeneralCandidateRepertoire)
            .sorted { lhs, rhs in
                if lhs.usageTier != rhs.usageTier {
                    return lhs.usageTier < rhs.usageTier
                }
                if lhs.firstPartyPhraseCount != rhs.firstPartyPhraseCount {
                    return lhs.firstPartyPhraseCount
                        > rhs.firstPartyPhraseCount
                }
                return lhs.sourceOrder < rhs.sourceOrder
            }
            .map(\.text)
        XCTAssertEqual(candidates.map(\.text), expectedOrder)
        XCTAssertEqual(candidates.first?.text, "我")
        XCTAssertTrue(candidates.allSatisfy { candidate in
            candidate.type == .character
                && candidate.baseFrequency != nil
                && candidate.userFrequency == 0
                && candidate.lastUsed == nil
                && !candidate.pinned
        })
    }

    func testTiFourthToneOffersTiAsASelectableCandidate() throws {
        let provider = CharacterCandidateProvider(dictionary: try makeDictionary())

        XCTAssertTrue(try provider.candidates(for: "ㄊㄧˋ").contains { candidate in
            candidate.text == "剔" && candidate.pronunciation == "ㄊㄧˋ"
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

    func testRemovePinFromCharacterKeepsItsLearningRecord() throws {
        let learning = LearningSpy()
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning
        )
        let candidate = Candidate(
            text: "鍵",
            pronunciation: "ㄐㄧㄢˋ",
            userFrequency: 12,
            pinned: true
        )

        XCTAssertTrue(provider.removePin(from: candidate))
        XCTAssertEqual(
            learning.characterPins,
            [
                CharacterPin(
                    character: "鍵",
                    pronunciation: "ㄐㄧㄢˋ",
                    pinned: false
                ),
            ]
        )
        XCTAssertTrue(learning.recordedSelections.isEmpty)
    }

    func testRemovePinRejectsCandidateThatIsNotPinned() throws {
        let learning = LearningSpy()
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning
        )

        XCTAssertFalse(
            provider.removePin(
                from: Candidate(text: "鍵", pronunciation: "ㄐㄧㄢˋ")
            )
        )
        XCTAssertTrue(learning.characterPins.isEmpty)
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
            try dictionary.candidateEntries(for: "ㄨㄛˇ")
                .filter(\.isInGeneralCandidateRepertoire)
                .map(\.text)
        )
    }

    func testUnknownPronunciationReturnsNoCandidates() throws {
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary()
        )

        XCTAssertEqual(try provider.candidates(for: "not-zhuyin"), [])
    }

    func testNeutralToneQueryWidensAcrossOtherTonesOfTheSameBody() throws {
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary()
        )

        let candidates = try provider.candidates(for: "˙ㄅㄛ")

        // 蔔 is genuinely neutral tone (˙ㄅㄛ, as in 蘿蔔); 播 is canonically
        // fourth tone (ㄅㄛˋ) but neutral tone is a common "don't care which
        // tone" shortcut, so it must still be reachable here — tagged with
        // its own real reading, not the neutral query.
        XCTAssertTrue(candidates.contains { $0.text == "蔔" && $0.pronunciation == "˙ㄅㄛ" })
        XCTAssertTrue(candidates.contains { $0.text == "播" && $0.pronunciation == "ㄅㄛˋ" })
        XCTAssertTrue(candidates.allSatisfy { $0.type == .character })
        XCTAssertEqual(candidates.map(\.text).count, Set(candidates.map(\.text)).count)
    }

    func testFirstToneQueryDoesNotWidenAcrossOtherTonesOfTheSameBody() throws {
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary()
        )

        let candidates = try provider.candidates(for: "ㄅㄛ")

        // Space explicitly selects first tone. A fourth-tone candidate must
        // not replace that reading and poison a following exact phrase query.
        XCTAssertTrue(candidates.contains { $0.text == "波" && $0.pronunciation == "ㄅㄛ" })
        XCTAssertFalse(candidates.contains { $0.text == "播" })
        XCTAssertTrue(candidates.allSatisfy { $0.type == .character })
        XCTAssertTrue(candidates.allSatisfy { $0.pronunciation == "ㄅㄛ" })
    }

    func testFirstToneJinIgnoresLearnedFourthToneAndKeepsTodayReachable() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let learning = LearningSpy()
        learning.recordsByPronunciation["ㄐㄧㄣˋ"] = [
            "進": CharacterLearningRecord(
                character: "進",
                pronunciation: "ㄐㄧㄣˋ",
                selectionCount: 12,
                lastSelectedAt: now,
                pinned: false
            ),
        ]
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning,
            now: { now }
        )

        let firstToneCandidates = try provider.candidates(for: "ㄐㄧㄣ")

        XCTAssertTrue(firstToneCandidates.contains { $0.text == "今" })
        XCTAssertFalse(firstToneCandidates.contains { $0.text == "進" })
        XCTAssertTrue(
            firstToneCandidates.allSatisfy { $0.pronunciation == "ㄐㄧㄣ" }
        )

        var buffer = CompositionBuffer()
        XCTAssertTrue(
            buffer.acceptCandidate(
                Candidate(text: "金", pronunciation: "ㄐㄧㄣ"),
                reason: .implicitPassThrough
            )
        )
        let secondSyllableCandidates = try provider.candidates(
            for: "ㄊㄧㄢ",
            phraseQueries: buffer.phraseLookupQueries(appending: "ㄊㄧㄢ")
        )

        let today = try XCTUnwrap(secondSyllableCandidates.first)
        XCTAssertEqual(today.text, "今天")
        XCTAssertEqual(today.pronunciationSequence, ["ㄐㄧㄣ", "ㄊㄧㄢ"])
    }

    func testExplicitlyTonedQueryIsNotWidened() throws {
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary()
        )

        let candidates = try provider.candidates(for: "ㄅㄛˊ")

        XCTAssertFalse(candidates.contains { $0.text == "波" })
        XCTAssertFalse(candidates.contains { $0.text == "播" })
        XCTAssertTrue(candidates.allSatisfy { $0.pronunciation == "ㄅㄛˊ" })
    }

    func testProviderOmitsCandidatesRejectedByDisplayPolicy() throws {
        let dictionary = try makeDictionary()
        let unfilteredProvider = CharacterCandidateProvider(
            dictionary: dictionary,
            showsRareCandidates: { true }
        )
        let rejectedCharacter = "𢳀"
        let provider = CharacterCandidateProvider(
            dictionary: dictionary,
            showsRareCandidates: { true },
            isCandidateDisplayable: { $0 != rejectedCharacter }
        )

        let unfiltered = try unfilteredProvider.candidates(for: "ㄇㄚ")
        let filtered = try provider.candidates(for: "ㄇㄚ")

        XCTAssertTrue(unfiltered.contains { $0.text == rejectedCharacter })
        XCTAssertFalse(filtered.contains { $0.text == rejectedCharacter })
        XCTAssertEqual(
            filtered.map(\.text),
            unfiltered.map(\.text).filter { $0 != rejectedCharacter }
        )
    }

    func testGeneralCandidateScopeKeepsEverydayCandidatesAndOmitsRareOnes() throws {
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary()
        )
        let rareProvider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            showsRareCandidates: { true }
        )

        let texts = try provider.candidates(for: "ㄇㄚ").map(\.text)
        let everydayCharacters = ["媽", "嗎", "摩", "螞", "嬤"]
        for character in everydayCharacters {
            XCTAssertTrue(texts.contains(character))
        }
        XCTAssertFalse(texts.contains("嬷"))

        XCTAssertTrue(
            try rareProvider.candidates(for: "ㄇㄚ").contains {
                $0.text == "嬷"
            }
        )
    }

    func testNarrowYiHeteronymsFollowEverydayYiCandidates() throws {
        let provider = CharacterCandidateProvider(dictionary: try makeDictionary())
        let texts = try provider.candidates(for: "ㄧˋ").map(\.text)

        for everydayCharacter in ["易", "益", "異", "意", "義", "譯"] {
            let everydayIndex = try XCTUnwrap(texts.firstIndex(of: everydayCharacter))
            let foodIndex = try XCTUnwrap(texts.firstIndex(of: "食"))
            let shootIndex = try XCTUnwrap(texts.firstIndex(of: "射"))
            XCTAssertLessThan(everydayIndex, foodIndex)
            XCTAssertLessThan(everydayIndex, shootIndex)
        }
    }

    func testYiDefaultsUseCapturedSelectionRankingBeforePhraseEvidence() throws {
        let provider = CharacterCandidateProvider(dictionary: try makeDictionary())
        let texts = try provider.candidates(for: "ㄧˋ").map(\.text)

        XCTAssertEqual(
            Array(texts.prefix(16)),
            [
                "意", "譯", "議", "益", "施", "異", "義", "憶",
                "易", "疫", "翌", "逸", "溢", "億", "毅", "誼",
            ]
        )
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
        XCTAssertTrue(candidates.prefix(2).allSatisfy(\.isUserPhrase))
        XCTAssertEqual(candidates.first?.baseFrequency, 0)
        XCTAssertGreaterThan(candidates[1].baseFrequency ?? 0, 0)
        XCTAssertEqual(
            learning.requestedPhraseReadings,
            [longReadings, shortReadings]
        )
        XCTAssertTrue(candidates.dropFirst(2).contains {
            $0.type == .character && !$0.isUserPhrase
        })
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
        XCTAssertTrue(
            candidates.filter { $0.type == .phrase }
                .allSatisfy { !$0.isUserPhrase }
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

    func testDeleteUserPhraseUsesExactValidatedIdentity() throws {
        let learning = LearningSpy()
        let provider = CharacterCandidateProvider(
            dictionary: try makeDictionary(),
            learning: learning
        )
        let readings = ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]

        XCTAssertTrue(
            provider.deleteUserPhrase(
                phrase: "久空",
                pronunciationSequence: readings
            )
        )
        XCTAssertFalse(
            provider.deleteUserPhrase(
                phrase: "錯誤",
                pronunciationSequence: ["ASCII", "ㄨˋ"]
            )
        )
        XCTAssertEqual(
            learning.deletedPhrases,
            [PhraseIdentity(phrase: "久空", readings: readings)]
        )
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

    private struct CharacterPin: Equatable {
        let character: String
        let pronunciation: String
        let pinned: Bool
    }

    private struct PhraseOperation: Equatable {
        let phrase: String
        let readings: [String]
        let date: Date
    }

    private struct PhraseIdentity: Equatable {
        let phrase: String
        let readings: [String]
    }

    private final class LearningSpy: UserLearningProviding {
        var recordsByPronunciation: [String: [String: CharacterLearningRecord]] = [:]
        var phraseRecordsByPronunciation: [[String]: [UserPhraseRecord]] = [:]
        var recordedSelections: [Selection] = []
        var characterPins: [CharacterPin] = []
        var requestedPhraseReadings: [[String]] = []
        var addedPhrases: [PhraseOperation] = []
        var recordedPhraseSelections: [PhraseOperation] = []
        var deletedPhrases: [PhraseIdentity] = []

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

        func setPinned(
            _ pinned: Bool,
            character: String,
            pronunciation: String
        ) {
            characterPins.append(
                CharacterPin(
                    character: character,
                    pronunciation: pronunciation,
                    pinned: pinned
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

        func deletePhrase(
            phrase: String,
            pronunciationSequence: [String]
        ) -> Bool {
            deletedPhrases.append(
                PhraseIdentity(
                    phrase: phrase,
                    readings: pronunciationSequence
                )
            )
            return true
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
