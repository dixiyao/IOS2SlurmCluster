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
    var debugLogs: [String] = []

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?

    func connect(bridgeURL: String, apiKey: String, ssh: [String: Any]) {
        let endpoint = parseConnectionEndpoint(bridgeURL)
        let normalizedHost = endpoint.host
        let wsURL = "ws://\(normalizedHost):\(endpoint.webSocketPort)"

        addDebug("Connect requested")
        addDebug("Raw bridge input: \(bridgeURL)")
        addDebug("Bridge host: \(normalizedHost)")
        addDebug("WebSocket URL: \(wsURL)")
        addDebug("Node bridge should listen on WebSocket port \(endpoint.webSocketPort)")

        guard let url = URL(string: wsURL) else {
            connectionError = "Invalid server host for WebSocket URL"
            addDebug("Failed to build URL from host input")
            return
        }

        let sshHost = (ssh["host"] as? String) ?? normalizedHost
        let sshUsername = (ssh["username"] as? String) ?? ""
        addDebug("SSH target: \(sshHost):22")
        addDebug("SSH username: \(sshUsername)")

        connectionError = nil
        session = URLSession(configuration: .default)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()
        addDebug("WebSocket task resumed")

        let connectMsg: [String: Any] = [
            "type": "connect",
            "ssh": ssh,
            "apiKey": apiKey
        ]

        sendJSON(connectMsg)
        listen(endpoint: endpoint)
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
        addDebug("Disconnected by user")
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        addDebug("Sending message: \((dict["type"] as? String) ?? "unknown")")
        webSocket?.send(.string(str)) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.connectionError = "WebSocket send failed: \(error.localizedDescription)"
                    self?.addDebug("Send error: \(error.localizedDescription)")
                    self?.isConnected = false
                }
            }
        }
    }

    private func listen(endpoint: (host: String, webSocketPort: Int)) {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(.string(let text)):
                    self?.addDebug("Received text frame")
                    self?.handleMessage(text)
                case .success(.data(let data)):
                    self?.addDebug("Received binary frame (\(data.count) bytes)")
                case .failure(let error):
                    self?.connectionError = self?.describeNetworkError(error, endpoint: endpoint) ?? "WebSocket receive failed: \(error.localizedDescription)"
                    self?.addDebug("Receive error: \(error.localizedDescription)")
                    self?.isConnected = false
                default:
                    break
                }
                if self?.webSocket != nil {
                    self?.listen(endpoint: endpoint)
                }
            }
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
            addDebug("Server confirmed connection")
        case "response":
            isWaiting = false
            if let content = msg["content"] as? String {
                messages.append(ChatMessage(content))
            }
            addDebug("Received agent response")
        case "error":
            isWaiting = false
            if let content = msg["content"] as? String {
                connectionError = content
                messages.append(ChatMessage(content, isSystem: true))
                addDebug("Server error: \(content)")
            }
        case "disconnected":
            isConnected = false
            isWaiting = false
            messages.append(ChatMessage("Disconnected from server.", isSystem: true))
            addDebug("Server disconnected")
        default:
            addDebug("Unhandled message type: \(type)")
            break
        }
    }

    private func parseConnectionEndpoint(_ input: String) -> (host: String, webSocketPort: Int) {
        let defaultPort = 3000
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ("", defaultPort) }

        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return (host, url.port ?? defaultPort)
        }

        let withoutScheme = trimmed
            .replacingOccurrences(of: "ws://", with: "")
            .replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")

        guard let firstPart = withoutScheme.split(separator: "/").first else {
            return (trimmed, defaultPort)
        }

        let hostPort = String(firstPart)
        if hostPort.hasPrefix("[") {
            if let endBracket = hostPort.firstIndex(of: "]") {
                let host = String(hostPort[...endBracket])
                let afterBracket = hostPort[hostPort.index(after: endBracket)...]
                if afterBracket.hasPrefix(":"), let parsedPort = Int(afterBracket.dropFirst()) {
                    return (host, parsedPort)
                }
                return (host, defaultPort)
            }
            return (hostPort, defaultPort)
        }

        if let colonIndex = hostPort.firstIndex(of: ":") {
            let host = String(hostPort[..<colonIndex])
            let portPart = String(hostPort[hostPort.index(after: colonIndex)...])
            if let parsedPort = Int(portPart) {
                return (host, parsedPort)
            }
            return (host, defaultPort)
        }

        return (hostPort, defaultPort)
    }

    private func describeNetworkError(_ error: Error, endpoint: (host: String, webSocketPort: Int)) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost:
                return "Could not connect to bridge ws://\(endpoint.host):\(endpoint.webSocketPort). Start client/server.js and ensure this port is reachable. SSH still uses port 22 via the bridge."
            case .networkConnectionLost:
                return "Bridge connection dropped for ws://\(endpoint.host):\(endpoint.webSocketPort). Check bridge logs and network path."
            case .timedOut:
                return "Connection to bridge timed out at ws://\(endpoint.host):\(endpoint.webSocketPort)."
            default:
                break
            }
        }
        return "WebSocket receive failed: \(error.localizedDescription)"
    }

    private func addDebug(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        debugLogs.append("[\(timestamp)] \(message)")

        if debugLogs.count > 80 {
            debugLogs.removeFirst(debugLogs.count - 80)
        }
    }
}
