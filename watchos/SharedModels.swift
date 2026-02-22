// Shared models that can be used by both iOS and WatchOS
// Copy this file to watchos folder as well

import Foundation

enum APIError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}

struct PromptRequest: Codable {
    let prompt: String
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case prompt
        case sessionId = "session_id"
    }
}

struct PromptResponse: Codable {
    let response: String
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case response
        case sessionId = "session_id"
    }
}
