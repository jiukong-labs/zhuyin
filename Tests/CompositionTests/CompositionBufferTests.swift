import Foundation
import XCTest

final class CompositionBufferTests: XCTestCase {
    func testAppendKeepsPerReadingUnitsAndRejectsMalformedOrDuplicateUnits() {
        var buffer = CompositionBuffer()
        let first = CompositionUnit(
            text: "久",
            pronunciation: "ㄐㄧㄡˇ"
        )

        XCTAssertTrue(buffer.append(first))
        XCTAssertFalse(buffer.append(first))
        XCTAssertFalse(buffer.append(CompositionUnit(text: "", pronunciation: "ㄎㄨㄥ")))
        XCTAssertFalse(buffer.append(CompositionUnit(text: "空", pronunciation: "")))
        XCTAssertEqual(buffer.units, [first])
        XCTAssertEqual(buffer.text, "久")
        XCTAssertEqual(buffer.pronunciationSequence, ["ㄐㄧㄡˇ"])
        XCTAssertTrue(buffer.pendingCandidateSelections.isEmpty)
    }

    func testAppendingTextClearsASelectionAndDoesNotCreateLearning() {
        var buffer = bufferWithThreeUnits()
        XCTAssertTrue(buffer.expandSelectionBackward())

        let appended = buffer.append(text: "器", pronunciation: "ㄑㄧˋ")

        XCTAssertEqual(appended?.text, "器")
        XCTAssertEqual(buffer.text, "輸入法器")
        XCTAssertFalse(buffer.hasSelection)
        XCTAssertTrue(buffer.pendingCandidateSelections.isEmpty)
    }

    func testCharacterCandidateCreatesPendingLearningForItsStableUnit() throws {
        var buffer = CompositionBuffer()
        let candidate = characterCandidate("鍵", reading: "ㄐㄧㄢˋ")

        XCTAssertTrue(buffer.acceptCandidate(candidate, reason: .number(4)))

        let unit = try XCTUnwrap(buffer.units.first)
        XCTAssertEqual(unit.text, "鍵")
        XCTAssertEqual(unit.pronunciation, "ㄐㄧㄢˋ")
        XCTAssertEqual(
            buffer.pendingCandidateSelections,
            [
                PendingCandidateSelection(
                    candidate: candidate,
                    reason: .number(4),
                    coveredUnitIDs: [unit.id]
                )
            ]
        )
    }

    func testMalformedCharacterCandidatesAreRejectedWithoutMutation() {
        let malformedCandidates = [
            Candidate(
                text: "",
                pronunciationSequence: ["ㄐㄧㄢˋ"],
                type: .character
            ),
            Candidate(
                text: "鍵",
                pronunciationSequence: [],
                type: .character
            ),
            Candidate(
                text: "鍵",
                pronunciationSequence: [""],
                type: .character
            ),
            Candidate(
                text: "鍵",
                pronunciationSequence: ["ㄐㄧㄢˋ", "ㄆㄢˊ"],
                type: .character
            )
        ]

        for candidate in malformedCandidates {
            var buffer = CompositionBuffer()
            XCTAssertFalse(buffer.acceptCandidate(candidate, reason: .space))
            XCTAssertEqual(buffer, CompositionBuffer())
        }
    }

    func testPhraseQueriesAreExactSuffixesOrderedLongestFirst() {
        var buffer = CompositionBuffer()
        let first = CompositionUnit(text: "原", pronunciation: "ㄩㄢˊ")
        let second = CompositionUnit(text: "住", pronunciation: "ㄓㄨˋ")
        let third = CompositionUnit(text: "民", pronunciation: "ㄇㄧㄣˊ")
        XCTAssertTrue(buffer.append(first))
        XCTAssertTrue(buffer.append(second))
        XCTAssertTrue(buffer.append(third))

        XCTAssertEqual(
            buffer.phraseLookupQueries(appending: "ㄗㄨˊ"),
            [
                CompositionPhraseQuery(
                    pronunciationSequence: ["ㄩㄢˊ", "ㄓㄨˋ", "ㄇㄧㄣˊ", "ㄗㄨˊ"],
                    existingSuffixUnitIDs: [first.id, second.id, third.id]
                ),
                CompositionPhraseQuery(
                    pronunciationSequence: ["ㄓㄨˋ", "ㄇㄧㄣˊ", "ㄗㄨˊ"],
                    existingSuffixUnitIDs: [second.id, third.id]
                ),
                CompositionPhraseQuery(
                    pronunciationSequence: ["ㄇㄧㄣˊ", "ㄗㄨˊ"],
                    existingSuffixUnitIDs: [third.id]
                )
            ]
        )
    }

    func testPhraseQueriesHonorBoundsAndRejectInvalidRequests() {
        var buffer = CompositionBuffer()
        for index in 0 ..< 5 {
            XCTAssertNotNil(
                buffer.append(
                    text: String(index),
                    pronunciation: "reading-\(index)"
                )
            )
        }

        let queries = buffer.phraseLookupQueries(
            appending: "final",
            minimumUnitCount: 3,
            maximumUnitCount: 4
        )
        XCTAssertEqual(queries.map(\.unitCount), [4, 3])
        XCTAssertEqual(
            queries.map(\.pronunciationSequence),
            [
                ["reading-2", "reading-3", "reading-4", "final"],
                ["reading-3", "reading-4", "final"]
            ]
        )

        XCTAssertTrue(buffer.phraseLookupQueries(appending: "").isEmpty)
        XCTAssertTrue(
            !buffer.phraseLookupQueries(
                appending: "final",
                minimumUnitCount: 1
            ).isEmpty
        )
        XCTAssertTrue(
            buffer.phraseLookupQueries(
                appending: "final",
                minimumUnitCount: 5,
                maximumUnitCount: 4
            ).isEmpty
        )
    }

    func testExactSuffixDoesNotTreatAPrefixOrPartialReadingAsAMatch() {
        var buffer = CompositionBuffer()
        XCTAssertNotNil(buffer.append(text: "輸", pronunciation: "ㄕㄨ"))
        XCTAssertNotNil(buffer.append(text: "入", pronunciation: "ㄖㄨˋ"))

        XCTAssertTrue(
            buffer.containsExactSuffix(
                pronunciationSequence: ["ㄕㄨ", "ㄖㄨˋ"]
            )
        )
        XCTAssertTrue(
            buffer.containsExactSuffix(pronunciationSequence: ["ㄖㄨˋ"])
        )
        XCTAssertFalse(
            buffer.containsExactSuffix(pronunciationSequence: ["ㄕㄨ"])
        )
        XCTAssertFalse(
            buffer.containsExactSuffix(pronunciationSequence: ["ㄖㄨ"])
        )
        XCTAssertFalse(
            buffer.containsExactSuffix(pronunciationSequence: [])
        )
    }

    func testPhraseCandidateReplacesMatchingSuffixAndSupersedesItsLearning() throws {
        var buffer = CompositionBuffer()
        let unrelated = characterCandidate("久", reading: "ㄐㄧㄡˇ")
        let oldFirst = characterCandidate("輸", reading: "ㄕㄨ")
        let oldSecond = characterCandidate("入", reading: "ㄖㄨˋ")
        XCTAssertTrue(buffer.acceptCandidate(unrelated, reason: .space))
        XCTAssertTrue(buffer.acceptCandidate(oldFirst, reason: .space))
        XCTAssertTrue(buffer.acceptCandidate(oldSecond, reason: .space))
        let oldSuffixIDs = buffer.units.suffix(2).map(\.id)

        let phrase = phraseCandidate(
            "輸入法",
            readings: ["ㄕㄨ", "ㄖㄨˋ", "ㄈㄚˇ"]
        )
        XCTAssertTrue(buffer.acceptCandidate(phrase, reason: .returnKey))

        XCTAssertEqual(buffer.text, "久輸入法")
        XCTAssertEqual(
            buffer.pronunciationSequence,
            ["ㄐㄧㄡˇ", "ㄕㄨ", "ㄖㄨˋ", "ㄈㄚˇ"]
        )
        XCTAssertTrue(Set(oldSuffixIDs).isDisjoint(with: buffer.units.map(\.id)))
        XCTAssertEqual(buffer.pendingCandidateSelections.count, 2)
        XCTAssertEqual(buffer.pendingCandidateSelections[0].candidate, unrelated)
        XCTAssertEqual(buffer.pendingCandidateSelections[1].candidate, phrase)
        XCTAssertEqual(
            buffer.pendingCandidateSelections[1].coveredUnitIDs,
            Array(buffer.units.suffix(3)).map(\.id)
        )
        XCTAssertEqual(buffer.pendingCandidateSelections[1].reason, .returnKey)
        _ = try XCTUnwrap(buffer.takeCommitSnapshot())
    }

    func testPhraseReplacementRequiresValidShapeAndExactExistingSuffix() {
        let invalidCandidates = [
            phraseCandidate("空", readings: ["ㄎㄨㄥ"]),
            phraseCandidate("輸入", readings: ["ㄕㄨ", "ㄖㄨˋ", "ㄈㄚˇ"]),
            phraseCandidate("輸入", readings: ["ㄕㄨ", ""]),
            phraseCandidate("輸入法", readings: ["ㄕㄨ", "ㄖㄨˋ", "ㄈㄚˇ"]),
            phraseCandidate(
                String(repeating: "詞", count: 65),
                readings: Array(repeating: "ㄘˊ", count: 65)
            )
        ]

        for candidate in invalidCandidates {
            var buffer = CompositionBuffer()
            XCTAssertNotNil(buffer.append(text: "錯", pronunciation: "ㄘㄨㄛˋ"))
            let before = buffer
            XCTAssertFalse(buffer.acceptCandidate(candidate, reason: .space))
            XCTAssertEqual(buffer, before)
        }
    }

    func testShiftSelectionExpandsAndShrinksAsAnEndAnchoredSuffix() {
        var buffer = bufferWithThreeUnits()

        XCTAssertTrue(buffer.expandSelectionBackward())
        XCTAssertEqual(buffer.selectedUnitRange, 2 ..< 3)
        XCTAssertNil(buffer.selectedPhrase)
        XCTAssertTrue(buffer.expandSelectionBackward())
        XCTAssertEqual(buffer.selectedUnitRange, 1 ..< 3)
        XCTAssertEqual(buffer.selectedPhrase?.text, "入法")
        XCTAssertEqual(
            buffer.selectedPhrase?.pronunciationSequence,
            ["ㄖㄨˋ", "ㄈㄚˇ"]
        )
        XCTAssertTrue(buffer.expandSelectionBackward())
        XCTAssertEqual(buffer.selectedPhrase?.text, "輸入法")
        XCTAssertFalse(buffer.expandSelectionBackward())

        XCTAssertTrue(buffer.shrinkSelectionForward())
        XCTAssertEqual(buffer.selectedPhrase?.text, "入法")
        XCTAssertTrue(buffer.shrinkSelectionForward())
        XCTAssertNil(buffer.selectedPhrase)
        XCTAssertTrue(buffer.shrinkSelectionForward())
        XCTAssertFalse(buffer.hasSelection)
        XCTAssertFalse(buffer.shrinkSelectionForward())
    }

    func testDirectionalSelectionExtendsFromRevisionFocusOnBothSides() throws {
        var buffer = bufferWithThreeUnits()
        let middleUnitID = try XCTUnwrap(buffer.units.dropFirst().first?.id)
        let lastUnitID = try XCTUnwrap(buffer.units.last?.id)

        XCTAssertTrue(
            buffer.extendSelectionLeft(
                from: .caret(followingUnitID: lastUnitID)
            )
        )
        XCTAssertEqual(buffer.selectedUnitRange, 0 ..< 2)
        XCTAssertEqual(buffer.selectedPhrase?.text, "輸入")

        XCTAssertTrue(buffer.extendSelectionRight(from: .bufferEdge))
        XCTAssertEqual(buffer.selectedUnitRange, 0 ..< 3)
        XCTAssertEqual(buffer.selectedPhrase?.text, "輸入法")

        buffer.clearSelection()
        XCTAssertTrue(
            buffer.extendSelectionRight(
                from: .caret(followingUnitID: middleUnitID)
            )
        )
        XCTAssertEqual(buffer.selectedUnitRange, 1 ..< 3)
        XCTAssertEqual(buffer.selectedPhrase?.text, "入法")
    }

    func testShiftLeftSelectsTheTwoReadingsBeforeThePositionedCaret() throws {
        var buffer = CompositionBuffer()
        for (text, pronunciation) in [
            ("合", "ㄏㄜˊ"),
            ("併", "ㄅㄧㄥˋ"),
            ("成", "ㄔㄥˊ"),
            ("一", "ㄧ"),
            ("行", "ㄏㄤˊ"),
        ] {
            XCTAssertNotNil(
                buffer.append(text: text, pronunciation: pronunciation)
            )
        }
        let unitAfterCaret = try XCTUnwrap(buffer.units.dropFirst(2).first)

        XCTAssertTrue(
            buffer.extendSelectionLeft(
                from: .caret(followingUnitID: unitAfterCaret.id)
            )
        )

        XCTAssertEqual(buffer.selectedUnitRange, 0 ..< 2)
        XCTAssertEqual(buffer.selectedPhrase?.text, "合併")
        XCTAssertEqual(
            buffer.markedSelectionRange,
            NSRange(location: 0, length: 2)
        )
    }

    func testPhraseSelectionStatusReportsOneAndMultipleCharacterRanges() throws {
        var buffer = bufferWithThreeUnits()
        let middleUnitID = try XCTUnwrap(buffer.units.dropFirst().first?.id)

        XCTAssertNil(buffer.phraseSelectionStatus)
        XCTAssertTrue(buffer.extendSelectionRight(from: .bufferEdge))
        XCTAssertEqual(
            buffer.phraseSelectionStatus,
            CompositionPhraseSelectionStatus(text: "輸", unitCount: 1)
        )
        XCTAssertEqual(
            buffer.phraseSelectionStatus?.displayText,
            "造詞範圍 1 音／1 字：【輸】　⇧←／→ 擴張　至少選 2 音，或 1 音加標點"
        )

        buffer.clearSelection()
        XCTAssertTrue(
            buffer.extendSelectionRight(
                from: .caret(followingUnitID: middleUnitID)
            )
        )
        XCTAssertEqual(
            buffer.phraseSelectionStatus?.displayText,
            "造詞範圍 2 音／2 字：【入法】　⇧←／→ 擴張"
        )
    }

    func testDirectionalSelectionCanStartAtEitherCompositionEnd() {
        var buffer = bufferWithThreeUnits()

        XCTAssertTrue(buffer.extendSelectionLeft(from: .bufferEdge))
        XCTAssertEqual(buffer.selectedUnitRange, 2 ..< 3)
        XCTAssertTrue(buffer.extendSelectionLeft(from: .bufferEdge))
        XCTAssertEqual(buffer.selectedPhrase?.text, "入法")

        buffer.clearSelection()
        XCTAssertTrue(buffer.extendSelectionRight(from: .bufferEdge))
        XCTAssertEqual(buffer.selectedUnitRange, 0 ..< 1)
        XCTAssertTrue(buffer.extendSelectionRight(from: .bufferEdge))
        XCTAssertEqual(buffer.selectedPhrase?.text, "輸入")
    }

    func testPositionedCaretAtTextEdgesSelectsOnlyTheAvailableSide() throws {
        var buffer = bufferWithThreeUnits()
        let firstUnitID = try XCTUnwrap(buffer.units.first?.id)

        XCTAssertTrue(
            buffer.extendSelectionLeft(
                from: .caret(followingUnitID: nil)
            )
        )
        XCTAssertEqual(buffer.selectedPhrase?.text, "入法")

        buffer.clearSelection()
        XCTAssertTrue(
            buffer.extendSelectionRight(
                from: .caret(followingUnitID: firstUnitID)
            )
        )
        XCTAssertEqual(buffer.selectedPhrase?.text, "輸入")

        buffer.clearSelection()
        XCTAssertFalse(
            buffer.extendSelectionLeft(
                from: .caret(followingUnitID: firstUnitID)
            )
        )
        XCTAssertFalse(
            buffer.extendSelectionRight(
                from: .caret(followingUnitID: nil)
            )
        )
        XCTAssertFalse(buffer.hasSelection)
    }

    func testDirectionalPhraseSelectionCanIncludePunctuation() throws {
        var buffer = CompositionBuffer()
        let first = try XCTUnwrap(
            buffer.append(text: "測", pronunciation: "ㄘㄜˋ")
        )
        XCTAssertNotNil(buffer.appendPunctuation("，"))
        XCTAssertNotNil(buffer.append(text: "試", pronunciation: "ㄕˋ"))

        XCTAssertTrue(
            buffer.extendSelectionRight(
                from: .caret(followingUnitID: first.id)
            )
        )
        XCTAssertEqual(buffer.selectedUnitRange, 0 ..< 1)
        XCTAssertTrue(buffer.extendSelectionRight(from: .bufferEdge))
        XCTAssertEqual(buffer.selectedUnitRange, 0 ..< 2)

        buffer.clearSelection()
        XCTAssertTrue(
            buffer.extendSelectionLeft(
                from: .caret(followingUnitID: nil)
            )
        )
        XCTAssertEqual(buffer.selectedUnitRange, 2 ..< 3)
        XCTAssertTrue(buffer.extendSelectionLeft(from: .bufferEdge))
        XCTAssertEqual(buffer.selectedUnitRange, 1 ..< 3)
    }

    func testMarkedSelectionRangeUsesUTF16RatherThanCharacterOffsets() {
        var buffer = CompositionBuffer()
        XCTAssertNotNil(buffer.append(text: "A", pronunciation: "a"))
        XCTAssertNotNil(
            buffer.append(
                text: "👨‍👩‍👧‍👦",
                pronunciation: "family"
            )
        )
        XCTAssertNotNil(buffer.append(text: "𠮷", pronunciation: "ji"))

        XCTAssertEqual(
            buffer.markedSelectionRange,
            NSRange(location: buffer.text.utf16.count, length: 0)
        )
        XCTAssertTrue(buffer.expandSelectionBackward())
        XCTAssertEqual(
            buffer.markedSelectionRange,
            NSRange(
                location: "A👨‍👩‍👧‍👦".utf16.count,
                length: "𠮷".utf16.count
            )
        )
        XCTAssertTrue(buffer.expandSelectionBackward())
        XCTAssertEqual(
            buffer.markedSelectionRange,
            NSRange(
                location: "A".utf16.count,
                length: "👨‍👩‍👧‍👦𠮷".utf16.count
            )
        )
    }

    func testRevisionFocusUsesUTF16CaretAndPhraseSelectionStillTakesPriority() throws {
        var buffer = CompositionBuffer()
        XCTAssertNotNil(buffer.append(text: "A", pronunciation: "a"))
        XCTAssertNotNil(buffer.append(text: "𐍈", pronunciation: "ji"))
        XCTAssertNotNil(buffer.append(text: "測", pronunciation: "ce"))
        let middleID = try XCTUnwrap(buffer.units.dropFirst().first?.id)

        XCTAssertEqual(
            buffer.markedSelectionRange(focusedUnitID: middleID),
            NSRange(location: 1, length: 0)
        )

        XCTAssertTrue(buffer.expandSelectionBackward())
        XCTAssertTrue(buffer.expandSelectionBackward())
        XCTAssertEqual(
            buffer.markedSelectionRange(focusedUnitID: middleID),
            NSRange(location: 1, length: 3)
        )
    }

    func testReadingCursorNavigationSkipsPunctuationAndStopsAtBothEnds() throws {
        var buffer = CompositionBuffer()
        let first = try XCTUnwrap(
            buffer.append(text: "測", pronunciation: "ㄘㄜˋ")
        )
        XCTAssertNotNil(buffer.appendPunctuation("，"))
        let second = try XCTUnwrap(
            buffer.append(text: "試", pronunciation: "ㄕˋ")
        )

        XCTAssertEqual(buffer.lastReadingUnitID, second.id)
        XCTAssertEqual(buffer.readingUnitID(before: nil), second.id)
        XCTAssertEqual(buffer.readingUnitID(before: second.id), first.id)
        XCTAssertNil(buffer.readingUnitID(before: first.id))
        XCTAssertEqual(buffer.readingUnitID(after: first.id), second.id)
        XCTAssertNil(buffer.readingUnitID(after: second.id))
        XCTAssertNil(buffer.readingUnitID(immediatelyBefore: first.id))
        XCTAssertNil(buffer.readingUnitID(immediatelyBefore: second.id))
        XCTAssertEqual(buffer.unitID(immediatelyAfter: first.id), buffer.units[1].id)
        XCTAssertEqual(buffer.unitID(immediatelyAfter: buffer.units[1].id), second.id)
        XCTAssertNil(buffer.unitID(immediatelyAfter: second.id))
    }

    func testCaretNavigationStopsOnBothSidesOfPunctuation() throws {
        var buffer = CompositionBuffer()
        let name = try XCTUnwrap(
            buffer.append(text: "名", pronunciation: "ㄇㄧㄥˊ")
        )
        let questionMark = try XCTUnwrap(buffer.appendPunctuation("？"))

        // 名？| -> 名|？ -> |名？
        XCTAssertEqual(
            buffer.caretAnchorUnitID(movingLeftFrom: nil),
            questionMark.id
        )
        XCTAssertEqual(
            buffer.caretAnchorUnitID(movingLeftFrom: questionMark.id),
            name.id
        )
        XCTAssertNil(buffer.caretAnchorUnitID(movingLeftFrom: name.id))

        // |名？ -> 名|？ -> 名？|
        XCTAssertEqual(
            buffer.caretAnchorUnitID(movingRightFrom: name.id),
            questionMark.id
        )
        XCTAssertNil(
            buffer.caretAnchorUnitID(movingRightFrom: questionMark.id)
        )
    }

    func testRevisionFocusReportsTheVisibleReadingPosition() throws {
        var buffer = CompositionBuffer()
        let first = try XCTUnwrap(
            buffer.append(text: "測", pronunciation: "ㄘㄜˋ")
        )
        XCTAssertNotNil(buffer.appendPunctuation("，"))
        let second = try XCTUnwrap(
            buffer.append(text: "試", pronunciation: "ㄕˋ")
        )

        XCTAssertEqual(
            buffer.revisionFocus(for: first.id),
            CompositionRevisionFocus(
                unitID: first.id,
                text: "測",
                pronunciation: "ㄘㄜˋ",
                readingPosition: 1,
                readingCount: 2
            )
        )
        XCTAssertEqual(
            buffer.revisionFocus(for: second.id)?.locatingDisplayText,
            "定位 2／2：試　ㄕˋ　⇧←／→ 造詞　⌫ 改左字音　Del 改右字音　↓ 選字"
        )
        XCTAssertEqual(
            buffer.revisionFocus(for: second.id)?.choosingDisplayText,
            "選字 2／2：試　←／→ 選候選　⌫ 改左字音　Del 改右字音　↑／Esc 返回"
        )
        XCTAssertNil(buffer.revisionFocus(for: UUID()))
    }

    func testReplacingARevisionUnitKeepsItsIDAndInvalidatesCoveredPhrase() throws {
        var buffer = CompositionBuffer()
        XCTAssertNotNil(buffer.append(text: "冊", pronunciation: "ㄘㄜˋ"))
        let phrase = phraseCandidate("測試", readings: ["ㄘㄜˋ", "ㄕˋ"])
        XCTAssertTrue(buffer.acceptCandidate(phrase, reason: .space))
        let revisedID = try XCTUnwrap(buffer.units.last?.id)

        let replacement = characterCandidate("市", reading: "ㄕˋ")
        XCTAssertTrue(
            buffer.replaceUnit(
                withID: revisedID,
                candidate: replacement,
                reason: .number(4)
            )
        )

        XCTAssertEqual(buffer.text, "測市")
        XCTAssertEqual(buffer.units.last?.id, revisedID)
        XCTAssertEqual(
            buffer.pendingCandidateSelections,
            [
                PendingCandidateSelection(
                    candidate: replacement,
                    reason: .number(4),
                    coveredUnitIDs: [revisedID]
                ),
            ]
        )
    }

    func testAcceptingTheCurrentRevisionCharacterPreservesPhraseLearning() throws {
        var buffer = CompositionBuffer()
        XCTAssertNotNil(buffer.append(text: "冊", pronunciation: "ㄘㄜˋ"))
        let phrase = phraseCandidate("測試", readings: ["ㄘㄜˋ", "ㄕˋ"])
        XCTAssertTrue(buffer.acceptCandidate(phrase, reason: .space))
        let pendingBefore = buffer.pendingCandidateSelections
        let revisedID = try XCTUnwrap(buffer.units.last?.id)

        XCTAssertTrue(
            buffer.replaceUnit(
                withID: revisedID,
                candidate: characterCandidate("試", reading: "ㄕˋ"),
                reason: .returnKey
            )
        )

        XCTAssertEqual(buffer.text, "測試")
        XCTAssertEqual(buffer.pendingCandidateSelections, pendingBefore)
    }

    func testRevisionRejectsWrongReadingAndPhraseCandidates() throws {
        var buffer = CompositionBuffer()
        let unit = try XCTUnwrap(
            buffer.append(text: "試", pronunciation: "ㄕˋ")
        )
        let before = buffer

        XCTAssertFalse(
            buffer.replaceUnit(
                withID: unit.id,
                candidate: characterCandidate("市", reading: "ㄕˊ"),
                reason: .space
            )
        )
        XCTAssertFalse(
            buffer.replaceUnit(
                withID: unit.id,
                candidate: phraseCandidate("測試", readings: ["ㄘㄜˋ", "ㄕˋ"]),
                reason: .space
            )
        )
        XCTAssertEqual(buffer, before)
    }

    func testRevisionPhraseQueryEndsAtFocusedUnit() throws {
        var buffer = CompositionBuffer()
        let first = try XCTUnwrap(
            buffer.append(text: "設", pronunciation: "ㄕㄜˋ")
        )
        let focused = try XCTUnwrap(
            buffer.append(text: "計", pronunciation: "ㄐㄧˋ")
        )
        XCTAssertNotNil(buffer.append(text: "得", pronunciation: "ㄉㄜˊ"))

        XCTAssertEqual(
            buffer.phraseLookupQueries(
                appending: focused.pronunciation,
                before: focused.id
            ),
            [
                CompositionPhraseQuery(
                    pronunciationSequence: ["ㄕㄜˋ", "ㄐㄧˋ"],
                    existingSuffixUnitIDs: [first.id]
                )
            ]
        )
    }

    func testRevisionCanReplaceExactPhraseEndingAtFocusedUnit() throws {
        var buffer = CompositionBuffer()
        XCTAssertNotNil(buffer.append(text: "社", pronunciation: "ㄕㄜˋ"))
        let focused = try XCTUnwrap(
            buffer.append(text: "計", pronunciation: "ㄐㄧˋ")
        )
        let trailing = try XCTUnwrap(
            buffer.append(text: "得", pronunciation: "ㄉㄜˊ")
        )
        let phrase = phraseCandidate(
            "設計",
            readings: ["ㄕㄜˋ", "ㄐㄧˋ"]
        )

        let replacements = buffer.replaceRevisionSuffix(
            endingAt: focused.id,
            candidate: phrase,
            reason: .number(1)
        )

        XCTAssertEqual(replacements.map(\.text), ["設", "計"])
        XCTAssertEqual(buffer.text, "設計得")
        XCTAssertEqual(buffer.units.last, trailing)
        XCTAssertEqual(
            buffer.pendingCandidateSelections.last,
            PendingCandidateSelection(
                candidate: phrase,
                reason: .number(1),
                coveredUnitIDs: replacements.map(\.id)
            )
        )
    }

    func testRevisionPhraseRejectsNonmatchingPrefixWithoutMutation() throws {
        var buffer = CompositionBuffer()
        XCTAssertNotNil(buffer.append(text: "設", pronunciation: "ㄕㄜˊ"))
        let focused = try XCTUnwrap(
            buffer.append(text: "計", pronunciation: "ㄐㄧˋ")
        )
        let before = buffer

        XCTAssertTrue(
            buffer.replaceRevisionSuffix(
                endingAt: focused.id,
                candidate: phraseCandidate(
                    "設計",
                    readings: ["ㄕㄜˋ", "ㄐㄧˋ"]
                ),
                reason: .space
            ).isEmpty
        )
        XCTAssertEqual(buffer, before)
    }

    func testDeleteFocusedUnitPrunesOnlySelectionsCoveringThatUnit() throws {
        var buffer = CompositionBuffer()
        let first = characterCandidate("測", reading: "ㄘㄜˋ")
        let second = characterCandidate("試", reading: "ㄕˋ")
        XCTAssertTrue(buffer.acceptCandidate(first, reason: .space))
        XCTAssertTrue(buffer.acceptCandidate(second, reason: .space))
        let secondID = try XCTUnwrap(buffer.units.last?.id)

        XCTAssertEqual(buffer.deleteUnit(withID: secondID)?.text, "試")
        XCTAssertEqual(buffer.text, "測")
        XCTAssertEqual(buffer.pendingCandidateSelections.map(\.candidate), [first])
    }

    func testBackspaceTargetIsTheImmediatelyPrecedingReading() throws {
        var adjacentBuffer = CompositionBuffer()
        let route = try XCTUnwrap(
            adjacentBuffer.append(text: "路", pronunciation: "ㄌㄨˋ")
        )
        let mirror = try XCTUnwrap(
            adjacentBuffer.append(text: "鏡", pronunciation: "ㄐㄧㄥˋ")
        )
        XCTAssertEqual(
            adjacentBuffer.readingUnitID(immediatelyBefore: mirror.id),
            route.id
        )
        XCTAssertNil(
            adjacentBuffer.readingUnitID(immediatelyBefore: route.id)
        )
        XCTAssertNil(
            adjacentBuffer.readingUnitID(immediatelyBefore: UUID())
        )

        XCTAssertNil(adjacentBuffer.unitID(immediatelyAfter: mirror.id))

        let punctuation = try XCTUnwrap(
            adjacentBuffer.appendPunctuation("，")
        )
        XCTAssertEqual(
            adjacentBuffer.unitID(immediatelyAfter: mirror.id),
            punctuation.id
        )
    }

    func testRevisionCandidateTargetsTheReadingImmediatelyBeforeTheCaret() throws {
        var buffer = CompositionBuffer()
        let route = try XCTUnwrap(
            buffer.append(text: "路", pronunciation: "ㄌㄨˋ")
        )
        let mirror = try XCTUnwrap(
            buffer.append(text: "鏡", pronunciation: "ㄐㄧㄥˋ")
        )

        XCTAssertEqual(
            buffer.revisionFocus(
                immediatelyBeforeCaretAt: mirror.id
            )?.unitID,
            route.id
        )
        XCTAssertEqual(
            buffer.revisionFocus(
                immediatelyBeforeCaretAt: nil
            )?.unitID,
            mirror.id
        )
        XCTAssertNil(
            buffer.revisionFocus(
                immediatelyBeforeCaretAt: route.id
            )
        )

        XCTAssertEqual(
            buffer.revisionFocusForCandidate(
                atCaretFollowing: mirror.id
            )?.unitID,
            route.id
        )
        XCTAssertEqual(
            buffer.revisionFocusForCandidate(
                atCaretFollowing: nil
            )?.unitID,
            mirror.id
        )
        XCTAssertEqual(
            buffer.revisionFocusForCandidate(
                atCaretFollowing: route.id
            )?.unitID,
            route.id
        )

        XCTAssertNotNil(buffer.appendPunctuation("，"))
        XCTAssertNil(
            buffer.revisionFocus(
                immediatelyBeforeCaretAt: nil
            )
        )
    }

    func testRevisionCandidateDoesNotCrossPunctuationAtAnInteriorCaret() throws {
        var buffer = CompositionBuffer()
        XCTAssertNotNil(buffer.append(text: "如", pronunciation: "ㄖㄨˊ"))
        XCTAssertNotNil(buffer.appendPunctuation("，"))
        let picture = try XCTUnwrap(
            buffer.append(text: "圖", pronunciation: "ㄊㄨˊ")
        )

        XCTAssertNil(
            buffer.revisionFocusForCandidate(
                atCaretFollowing: picture.id
            )
        )
    }

    func testDeleteBackwardRemovesOneUnitAndOnlyItsPendingLearning() {
        var buffer = CompositionBuffer()
        let first = characterCandidate("輸", reading: "ㄕㄨ")
        let second = characterCandidate("入", reading: "ㄖㄨˋ")
        XCTAssertTrue(buffer.acceptCandidate(first, reason: .space))
        XCTAssertTrue(buffer.acceptCandidate(second, reason: .mouse))

        XCTAssertEqual(buffer.deleteBackward().map(\.text), ["入"])
        XCTAssertEqual(buffer.text, "輸")
        XCTAssertEqual(
            buffer.pendingCandidateSelections.map(\.candidate),
            [first]
        )
        XCTAssertEqual(buffer.deleteBackward().map(\.text), ["輸"])
        XCTAssertTrue(buffer.pendingCandidateSelections.isEmpty)
        XCTAssertTrue(buffer.deleteBackward().isEmpty)
    }

    func testDeleteBackwardRemovesTheWholeSelectedSuffixAndPrunesEvents() {
        var buffer = CompositionBuffer()
        let first = characterCandidate("輸", reading: "ㄕㄨ")
        let second = characterCandidate("入", reading: "ㄖㄨˋ")
        let third = characterCandidate("法", reading: "ㄈㄚˇ")
        XCTAssertTrue(buffer.acceptCandidate(first, reason: .space))
        XCTAssertTrue(buffer.acceptCandidate(second, reason: .space))
        XCTAssertTrue(buffer.acceptCandidate(third, reason: .space))
        XCTAssertTrue(buffer.expandSelectionBackward())
        XCTAssertTrue(buffer.expandSelectionBackward())

        XCTAssertEqual(buffer.deleteBackward().map(\.text), ["入", "法"])
        XCTAssertEqual(buffer.text, "輸")
        XCTAssertFalse(buffer.hasSelection)
        XCTAssertEqual(
            buffer.pendingCandidateSelections.map(\.candidate),
            [first]
        )
    }

    func testDeletingAnyPartOfAPhrasePrunesTheWholePhraseLearningEvent() {
        var buffer = CompositionBuffer()
        XCTAssertNotNil(buffer.append(text: "輸", pronunciation: "ㄕㄨ"))
        let phrase = phraseCandidate("輸入", readings: ["ㄕㄨ", "ㄖㄨˋ"])
        XCTAssertTrue(buffer.acceptCandidate(phrase, reason: .space))
        XCTAssertEqual(buffer.pendingCandidateSelections.count, 1)

        XCTAssertEqual(buffer.deleteBackward().map(\.text), ["入"])
        XCTAssertEqual(buffer.text, "輸")
        XCTAssertTrue(buffer.pendingCandidateSelections.isEmpty)
    }

    func testTakeCommitSnapshotIsTypedAtomicAndConsumableOnlyOnce() throws {
        var buffer = CompositionBuffer()
        let candidate = characterCandidate("鍵", reading: "ㄐㄧㄢˋ")
        XCTAssertTrue(buffer.acceptCandidate(candidate, reason: .mouse))
        XCTAssertNotNil(buffer.append(text: "ㄆ", pronunciation: "ㄆ"))
        XCTAssertTrue(buffer.expandSelectionBackward())

        let snapshot = try XCTUnwrap(buffer.takeCommitSnapshot())

        XCTAssertEqual(snapshot.text, "鍵ㄆ")
        XCTAssertEqual(snapshot.pronunciationSequence, ["ㄐㄧㄢˋ", "ㄆ"])
        XCTAssertEqual(snapshot.units.map(\.text), ["鍵", "ㄆ"])
        XCTAssertEqual(
            snapshot.pendingCandidateSelections.map(\.candidate),
            [candidate]
        )
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertFalse(buffer.hasSelection)
        XCTAssertTrue(buffer.pendingCandidateSelections.isEmpty)
        XCTAssertNil(buffer.takeCommitSnapshot())
    }

    func testDiscardDropsTextSelectionAndPendingLearning() {
        var buffer = CompositionBuffer()
        XCTAssertTrue(
            buffer.acceptCandidate(
                characterCandidate("鍵", reading: "ㄐㄧㄢˋ"),
                reason: .space
            )
        )
        XCTAssertTrue(buffer.expandSelectionBackward())

        buffer.discard()

        XCTAssertEqual(buffer, CompositionBuffer())
        XCTAssertNil(buffer.takeCommitSnapshot())
    }

    func testClearingSelectionReportsWhetherStateChanged() {
        var buffer = bufferWithThreeUnits()
        XCTAssertFalse(buffer.clearSelection())
        XCTAssertTrue(buffer.expandSelectionBackward())
        XCTAssertTrue(buffer.clearSelection())
        XCTAssertFalse(buffer.clearSelection())
    }

    func testInsertLiteralReadingLandsRightBeforeTheAnchorUnit() throws {
        var buffer = bufferWithThreeUnits()
        let anchorID = try XCTUnwrap(buffer.units.first?.id)
        let followingIDs = Array(buffer.units.dropFirst()).map(\.id)

        let inserted = try XCTUnwrap(
            buffer.insert(text: "ㄖㄨˋ", pronunciation: "ㄖㄨˋ", before: anchorID)
        )

        XCTAssertEqual(buffer.text, "ㄖㄨˋ輸入法")
        XCTAssertEqual(
            buffer.units.map(\.id),
            [inserted.id, anchorID] + followingIDs
        )
        XCTAssertFalse(buffer.hasSelection)
    }

    func testInsertingBeforeAnUnknownAnchorFailsWithoutMutation() {
        var buffer = bufferWithThreeUnits()
        let before = buffer

        XCTAssertNil(
            buffer.insert(text: "字", pronunciation: "ㄗˋ", before: UUID())
        )
        XCTAssertEqual(
            buffer.insertCandidate(
                characterCandidate("字", reading: "ㄗˋ"),
                before: UUID(),
                reason: .space
            ),
            []
        )
        XCTAssertEqual(buffer, before)
    }

    func testInsertingACharacterCandidateLandsBeforeTheAnchorAndLearnsIt() throws {
        var buffer = bufferWithThreeUnits()
        let anchorID = try XCTUnwrap(buffer.units.first?.id)
        let followingIDs = Array(buffer.units.dropFirst()).map(\.id)
        let candidate = characterCandidate("了", reading: "ㄌㄜ˙")

        let inserted = buffer.insertCandidate(
            candidate,
            before: anchorID,
            reason: .number(2)
        )

        let insertedUnit = try XCTUnwrap(inserted.first)
        XCTAssertEqual(inserted.count, 1)
        XCTAssertEqual(insertedUnit.text, "了")
        XCTAssertEqual(buffer.text, "了輸入法")
        // The anchor keeps its identity and position right after the new
        // unit, exactly like a text cursor sitting before it, rather than the
        // candidate landing at the end.
        XCTAssertEqual(
            buffer.units.map(\.id),
            [insertedUnit.id, anchorID] + followingIDs
        )
        XCTAssertEqual(
            buffer.pendingCandidateSelections,
            [
                PendingCandidateSelection(
                    candidate: candidate,
                    reason: .number(2),
                    coveredUnitIDs: [insertedUnit.id]
                )
            ]
        )
    }

    func testInsertingAPhraseCandidateOnlyConsumesReadingsBeforeTheAnchor() throws {
        var buffer = bufferWithThreeUnits()
        let anchorID = try XCTUnwrap(buffer.units.dropFirst().first?.id)
        let anchorUnit = try XCTUnwrap(buffer.units.dropFirst().first)
        let trailingUnit = try XCTUnwrap(buffer.units.last)

        let phrase = phraseCandidate("書局", readings: ["ㄕㄨ", "ㄐㄩˊ"])
        let inserted = buffer.insertCandidate(
            phrase,
            before: anchorID,
            reason: .returnKey
        )

        XCTAssertEqual(inserted.map(\.text), ["書", "局"])
        // Only the reading before the anchor was consumed into the phrase;
        // the anchor itself and anything after it are untouched.
        XCTAssertEqual(buffer.text, "書局入法")
        XCTAssertTrue(buffer.units.contains(anchorUnit))
        XCTAssertEqual(buffer.units.last, trailingUnit)
        XCTAssertEqual(
            buffer.pendingCandidateSelections.last?.coveredUnitIDs,
            inserted.map(\.id)
        )
    }

    func testPhraseLookupQueriesBeforeAnchorIgnoreTheAnchorAndWhatFollowsIt() throws {
        let buffer = bufferWithThreeUnits()
        let anchorID = try XCTUnwrap(buffer.units.dropFirst().first?.id)
        let firstID = try XCTUnwrap(buffer.units.first?.id)

        let queries = buffer.phraseLookupQueries(
            appending: "final",
            before: anchorID
        )

        // Only what precedes the anchor may combine with the new reading;
        // the anchor ("入") and the trailing "法" unit must never appear.
        XCTAssertEqual(
            queries,
            [
                CompositionPhraseQuery(
                    pronunciationSequence: ["ㄕㄨ", "final"],
                    existingSuffixUnitIDs: [firstID]
                )
            ]
        )
        XCTAssertTrue(
            buffer.phraseLookupQueries(appending: "final", before: UUID())
                .isEmpty
        )
    }

    private func bufferWithThreeUnits() -> CompositionBuffer {
        var buffer = CompositionBuffer()
        XCTAssertNotNil(buffer.append(text: "輸", pronunciation: "ㄕㄨ"))
        XCTAssertNotNil(buffer.append(text: "入", pronunciation: "ㄖㄨˋ"))
        XCTAssertNotNil(buffer.append(text: "法", pronunciation: "ㄈㄚˇ"))
        return buffer
    }

    private func characterCandidate(
        _ text: String,
        reading: String
    ) -> Candidate {
        Candidate(text: text, pronunciation: reading)
    }

    private func phraseCandidate(
        _ text: String,
        readings: [String]
    ) -> Candidate {
        Candidate(
            text: text,
            pronunciationSequence: readings,
            type: .phrase
        )
    }
}
