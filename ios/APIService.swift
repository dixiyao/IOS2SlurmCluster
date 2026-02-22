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

class APIService: ObservableObject {
    @Published var isLoading = false
    private let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func sendPrompt(_ prompt: String, sessionId: String? = nil) async throws -> String {
        guard let url = URL(string: "\(config.serverURL)/api/prompt") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = PromptRequest(prompt: prompt, sessionId: sessionId)

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw APIError.decodingError(error)
        }

        DispatchQueue.main.async {
            self.isLoading = true
        }

        defer {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw APIError.invalidResponse
            }

            let decodedResponse = try JSONDecoder().decode(PromptResponse.self, from: data)
            return decodedResponse.response

        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    func resetConversation() async throws {
        guard let url = URL(string: "\(config.serverURL)/api/reset") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
    }

    func checkServerHealth() async throws -> Bool {
        guard let url = URL(string: "\(config.serverURL)/") else {
            throw APIError.invalidURL
        }

        let (_, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return false
        }

        return true
    }
}
