import InputMethodKit

enum VisibleCandidateSelection: Equatable {
    case selected(String)
    case emptySlot
    case notReady
    case selectionFailed
}

final class SystemCandidatePresenter {
    private let panel: IMKCandidates

    init?(server: IMKServer) {
        guard let panel = IMKCandidates(
            server: server,
            panelType: kIMKSingleRowSteppingCandidatePanel
        ) else {
            return nil
        }

        self.panel = panel
        panel.setAttributes([
            IMKCandidatesSendServerKeyEventFirst: NSNumber(value: true)
        ])
        panel.setDismissesAutomatically(true)
    }

    var isVisible: Bool {
        panel.isVisible()
    }

    var selectedCandidateText: String? {
        panel.selectedCandidateString()?.string
    }

    func selectCandidate(_ candidate: String) -> Bool {
        let identifier = panel.candidateStringIdentifier(candidate as NSString)
        guard identifier != NSNotFound else {
            return false
        }

        return panel.selectCandidate(withIdentifier: identifier)
    }

    func candidate(
        atVisibleIndex visibleIndex: Int,
        from session: CandidateSession
    ) -> VisibleCandidateSelection {
        guard panel.isVisible() else {
            return .notReady
        }

        guard visibleIndex >= 0 else {
            return .emptySlot
        }

        let identifier = panel.candidateIdentifier(
            atLineNumber: visibleIndex
        )
        guard identifier != NSNotFound else {
            let firstVisibleIdentifier = panel.candidateIdentifier(
                atLineNumber: 0
            )
            return firstVisibleIdentifier == NSNotFound
                ? .notReady
                : .emptySlot
        }

        guard let candidate = session.candidate(
            matchingIdentifier: identifier,
            using: {
                panel.candidateStringIdentifier($0 as NSString)
            }
        ) else {
            return .selectionFailed
        }

        return .selected(candidate)
    }

    func updateAndShow() {
        panel.update()
        panel.show(kIMKLocateCandidatesBelowHint)
    }

    func hide() {
        panel.hide()
    }
}
