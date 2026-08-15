enum CandidateInputSourcePolicy {
    static func shouldFinishPresentation(
        currentInputSourceID: String?,
        ownInputSourceID: String?
    ) -> Bool {
        guard let currentInputSourceID,
              let ownInputSourceID,
              !ownInputSourceID.isEmpty else {
            return false
        }

        return currentInputSourceID != ownInputSourceID
    }
}
