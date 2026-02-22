import Foundation

class WatchAPIService: ObservableObject {
    @Published var isLoading = false
    private let config: WatchConfig

    init(config: WatchConfig) {
        self.config = config
    }

    func sendPrompt(_ prompt: String) async throws -> String {
        guard let url = URL(string: "\(config.serverURL)/api/prompt") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let requestBody = PromptRequest(prompt: prompt, sessionId: nil)

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
}
