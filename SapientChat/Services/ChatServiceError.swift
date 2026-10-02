import Foundation

nonisolated enum ChatServiceError: LocalizedError, Sendable {
    case noModelLoaded

    var errorDescription: String? {
        switch self {
        case .noModelLoaded: "No model is loaded."
        }
    }
}
