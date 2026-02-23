import Foundation
import Observation
import Citadel
import NIO
import NIOSSH

@MainActor @Observable
final class SSHManager {
    var messages: [ChatMessage] = []
    var isConnected = false
    var isWaiting = false
    var connectionError: String?
    var debugLogs: [String] = []
    
    private var apiKey: String = ""
    
    private var sshClient: SSHClient?
    
    func connect(host: String, port: Int, username: String, password: String, apiKey: String) {
        self.apiKey = apiKey
        addDebug("Direct SSH connection requested")
        addDebug("SSH target: \(host):\(port)")
        addDebug("Username: \(username)")
        
        Task {
            do {
                addDebug("Connecting to SSH server...")
                
                // Create SSH client settings
                let settings = SSHClientSettings(
                    host: host,
                    port: port,
                    authenticationMethod: { .passwordBased(username: username, password: password) },
                    hostKeyValidator: .acceptAnything()
                )
                
                // Connect to SSH server
                let client = try await SSHClient.connect(to: settings)
                sshClient = client
                addDebug("SSH connected successfully")
                
                // Create SSH exec channel to communicate with agent
                // We'll use the SSH connection to execute commands that talk to local agent
                isConnected = true
                messages.append(ChatMessage("Connected to SSH server.", isSystem: true))
                addDebug("Connection fully established")
                
            } catch {
                connectionError = "SSH connection failed: \(error.localizedDescription)"
                addDebug("SSH error: \(error)")
                isConnected = false
            }
        }
    }
    
    func sendMessage(_ text: String) {
        guard isConnected, !isWaiting, let client = sshClient else { return }
        messages.append(ChatMessage(text, isUser: true))
        isWaiting = true
        
        Task {
            do {
                // Create JSON payload for the agent
                let payload: [String: String] = ["content": text, "api_key": apiKey]
                let jsonData = try JSONSerialization.data(withJSONObject: payload)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                
                // Use nc (netcat) to send to local agent socket
                let command = "echo '\(jsonString)' | nc 127.0.0.1 8888"
                addDebug("Executing: \(command)")
                
                var output = try await client.executeCommand(command)
                
                // Parse the response
                if let responseString = output.readString(length: output.readableBytes),
                   !responseString.isEmpty {
                    let lines = responseString.components(separatedBy: "\n")
                    for line in lines {
                        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        
                        if let data = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let content = json["content"] as? String {
                            messages.append(ChatMessage(content))
                        } else {
                            messages.append(ChatMessage(line))
                        }
                    }
                    addDebug("Received response")
                } else {
                    addDebug("No response from agent")
                }
                
                isWaiting = false
                
            } catch {
                connectionError = "Send failed: \(error.localizedDescription)"
                addDebug("Send error: \(error)")
                isWaiting = false
            }
        }
    }
    
    func disconnect() {
        Task {
            try? await sshClient?.close()
            sshClient = nil
        }
        isConnected = false
        isWaiting = false
        messages = []
        addDebug("Disconnected by user")
    }
    
    fileprivate func addDebug(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        debugLogs.append("[\(timestamp)] \(message)")
        
        if debugLogs.count > 80 {
            debugLogs.removeFirst(debugLogs.count - 80)
        }
    }
}
