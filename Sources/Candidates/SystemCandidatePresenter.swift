import InputMethodKit

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

    func updateAndShow() {
        panel.update()
        panel.show(kIMKLocateCandidatesBelowHint)
    }

    func hide() {
        panel.hide()
    }
}
