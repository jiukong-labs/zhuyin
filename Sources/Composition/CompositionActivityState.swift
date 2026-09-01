import Foundation

/// One definition of whether unfinished input still belongs to the current
/// composition. Keeping this pure lets UI state follow the input engine
/// without depending on marked-text rendering supplied by the client app.
enum CompositionActivityState {
    static func isActive(
        hasCandidateSession: Bool,
        inputSessionHasComposition: Bool,
        compositionBufferIsEmpty: Bool
    ) -> Bool {
        hasCandidateSession
            || inputSessionHasComposition
            || !compositionBufferIsEmpty
    }
}
