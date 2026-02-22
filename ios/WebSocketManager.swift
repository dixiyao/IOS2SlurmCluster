import Foundation
import Observation

struct ChatMessage: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let isSystem: Bool

    init(_ text: String, isUser: Bool = false, isSystem: Bool = false) {
        self.text = text
        self.isUser = isUser
        self.isSystem = isSystem
    }
}

@MainActor @Observable
final class WebSocketManager {
    var messages: [ChatMessage] = []
    var isConnected = false
    var isWaiting = false
    var connectionError: String?

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?

    func connect(serverURL: String, ssh: [String: Any]) {
        guard let url = URL(string: serverURL) else {
            connectionError = "Invalid server URL"
            return
        }

        connectionError = nil
        session = URLSession(configuration: .default)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        let connectMsg: [String: Any] = [
            "type": "connect",
            "ssh": ssh
        ]

        sendJSON(connectMsg)
        listen()
    }

    func sendMessage(_ text: String) {
        guard isConnected, !isWaiting else { return }
        messages.append(ChatMessage(text, isUser: true))
        isWaiting = true
        let msg: [String: Any] = ["type": "message", "content": text]
        sendJSON(msg)
    }

    func disconnect() {
        let msg: [String: Any] = ["type": "disconnect"]
        sendJSON(msg)
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        isWaiting = false
        messages = []
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(str)) { _ in }
    }

    private func listen() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(.string(let text)):
                    self?.handleMessage(text)
                case .failure(let error):
                    self?.connectionError = error.localizedDescription
                    self?.isConnected = false
                default:
                    break
                }
            }
            self?.listen()
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = msg["type"] as? String else { return }

        switch type {
        case "connected":
            isConnected = true
            isWaiting = false
            messages.append(ChatMessage("Connected to remote agent.", isSystem: true))
        case "response":
            isWaiting = false
            if let content = msg["content"] as? String {
                messages.append(ChatMessage(content))
            }
        case "error":
            isWaiting = false
            if let content = msg["content"] as? String {
                connectionError = content
                messages.append(ChatMessage(content, isSystem: true))
            }
        case "disconnected":
            isConnected = false
            isWaiting = false
            messages.append(ChatMessage("Disconnected from server.", isSystem: true))
        default:
            break
        }
    }
}
