import AppKit
import Carbon
import XCTest

final class CandidateCommandRouterTests: XCTestCase {
    func testCompactDownExpandsWithoutMovingSelection() {
        XCTAssertEqual(command(kVK_DownArrow), .expand)
    }

    func testExpandedArrowsNavigateInGridDirections() {
        XCTAssertEqual(
            command(kVK_DownArrow, isExpanded: true),
            .navigate(.down)
        )
        XCTAssertEqual(
            command(kVK_UpArrow, isExpanded: true),
            .navigate(.up)
        )
        XCTAssertEqual(command(kVK_LeftArrow), .navigate(.previous))
        XCTAssertEqual(command(kVK_RightArrow), .navigate(.next))
    }

    func testMapsPagingAndBoundaryNavigation() {
        XCTAssertEqual(command(kVK_Home), .navigate(.first))
        XCTAssertEqual(command(kVK_End), .navigate(.last))
        XCTAssertEqual(command(kVK_PageUp), .navigate(.previousPage))
        XCTAssertEqual(command(kVK_PageDown), .navigate(.nextPage))
    }

    func testMapsEverySelectionNumber() {
        let selectionKeys = [
            kVK_ANSI_1,
            kVK_ANSI_2,
            kVK_ANSI_3,
            kVK_ANSI_4,
            kVK_ANSI_5,
            kVK_ANSI_6,
            kVK_ANSI_7,
            kVK_ANSI_8,
            kVK_ANSI_9
        ]

        for (index, keyCode) in selectionKeys.enumerated() {
            XCTAssertEqual(command(keyCode), .select(index))
        }
    }

    func testCompactMappedBodyNumberContinuesWithNextSyllable() {
        let bodyComponents: [BopomofoComponent] = [
            .initial(.b),
            .medial(.i),
            .final(.an)
        ]

        for (index, component) in bodyComponents.enumerated() {
            XCTAssertNil(
                command(
                    kVK_ANSI_1 + index,
                    mappedBopomofoComponent: component
                )
            )
        }
    }

    func testCompactHighlightedBodyNumberConfirmsItsCandidate() {
        XCTAssertEqual(
            command(
                kVK_ANSI_1,
                mappedBopomofoComponent: .initial(.b),
                highlightedSelectionKeyIndex: 0
            ),
            .select(0)
        )
        XCTAssertEqual(
            command(
                kVK_ANSI_5,
                mappedBopomofoComponent: .initial(.zh),
                highlightedSelectionKeyIndex: 4
            ),
            .select(4)
        )
    }

    func testCompactDifferentBodyNumberStillContinuesComposition() {
        XCTAssertNil(
            command(
                kVK_ANSI_5,
                mappedBopomofoComponent: .initial(.zh),
                highlightedSelectionKeyIndex: 0
            )
        )
    }

    func testCompactRevisionNumberAlwaysSelectsPrintedCandidate() {
        XCTAssertEqual(
            command(
                kVK_ANSI_2,
                isExplicitSelectionContext: true,
                mappedBopomofoComponent: .initial(.d),
                highlightedSelectionKeyIndex: 0
            ),
            .select(1)
        )
    }

    func testCompactMappedToneNumberStillSelectsCandidate() {
        XCTAssertEqual(
            command(
                kVK_ANSI_3,
                mappedBopomofoComponent: .tone(.third)
            ),
            .select(2)
        )
    }

    func testExpandedMappedBodyNumberSelectsCandidate() {
        XCTAssertEqual(
            command(
                kVK_ANSI_1,
                isExpanded: true,
                mappedBopomofoComponent: .initial(.b)
            ),
            .select(0)
        )
    }

    func testMapsConfirmationCancellationAndEditing() {
        XCTAssertEqual(command(kVK_Space), .commitFirst)
        XCTAssertEqual(command(kVK_Return), .commitHighlighted)
        XCTAssertEqual(command(kVK_ANSI_KeypadEnter), .commitHighlighted)
        XCTAssertEqual(command(kVK_Escape), .cancel)
        XCTAssertEqual(command(kVK_Delete), .deleteBackward)
    }

    func testAllowsFlagsInherentToNavigationKeys() {
        for flags: NSEvent.ModifierFlags in [
            .function,
            .numericPad,
            [.function, .numericPad]
        ] {
            XCTAssertEqual(
                command(kVK_RightArrow, modifierFlags: flags),
                .navigate(.next)
            )
        }
    }

    func testRejectsShortcutModifiers() {
        for flags: NSEvent.ModifierFlags in [
            .command,
            .control,
            .option,
            .shift,
            [.command, .function]
        ] {
            XCTAssertNil(
                command(kVK_RightArrow, modifierFlags: flags)
            )
            XCTAssertNil(command(kVK_ANSI_2, modifierFlags: flags))
        }
    }

    func testLeavesUnrelatedKeysAlone() {
        for keyCode in [kVK_ANSI_0, kVK_ANSI_A, kVK_ForwardDelete] {
            XCTAssertNil(command(keyCode))
        }
    }

    private func command(
        _ keyCode: Int,
        modifierFlags: NSEvent.ModifierFlags = [],
        isExpanded: Bool = false,
        isExplicitSelectionContext: Bool = false,
        mappedBopomofoComponent: BopomofoComponent? = nil,
        highlightedSelectionKeyIndex: Int? = nil
    ) -> CandidateCommand? {
        CandidateCommandRouter.command(
            keyCode: UInt16(keyCode),
            modifierFlags: modifierFlags,
            isExpanded: isExpanded,
            isExplicitSelectionContext: isExplicitSelectionContext,
            mappedBopomofoComponent: mappedBopomofoComponent,
            highlightedSelectionKeyIndex: highlightedSelectionKeyIndex
        )
    }
}
