import Foundation
import Observation
import Citadel
import NIO

@MainActor @Observable
final class SSHManager {
    var messages: [ChatMessage] = []
    var isConnected = false
    var isWaiting = false
    var connectionError: String?
    var debugLogs: [String] = []
    
    private var agentBuffer = ""
    private var apiKey: String = ""
    
    private var sshClient: SSHClient?
    private var tunnelChannel: Channel?
    
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
                    authenticationMethod: .passwordBased(username: username, password: password),
                    hostKeyValidator: .acceptAnything()
                )
                
                // Connect to SSH server
                let client = try await SSHClient.connect(to: settings)
                sshClient = client
                addDebug("SSH connected, creating tunnel...")
                
                // Create tunnel to agent socket (127.0.0.1:8888 on remote server)
                let address = try SocketAddress(ipAddress: "127.0.0.1", port: 8888)
                let channel = try await client.createDirectTCPIPChannel(
                    using: SSHChannelType.DirectTCPIP(
                        targetHost: "127.0.0.1",
                        targetPort: 8888,
                        originatorAddress: address
                    )
                ) { channel in
                    channel
                }
                tunnelChannel = channel
                addDebug("Tunnel established to agent")
                
                isConnected = true
                messages.append(ChatMessage("Connected to remote agent via SSH.", isSystem: true))
                
                // Start reading agent responses
                readAgentResponses()
                
            } catch {
                connectionError = "SSH connection failed: \(error.localizedDescription)"
                addDebug("SSH error: \(error)")
                isConnected = false
            }
        }
    }
    
    func sendMessage(_ text: String) {
        guard isConnected, !isWaiting, let channel = tunnelChannel else { return }
        messages.append(ChatMessage(text, isUser: true))
        isWaiting = true
        
        Task {
            do {
                // Send JSON message to agent
                let payload = try JSONSerialization.data(withJSONObject: ["content": text])
                var message = String(data: payload, encoding: .utf8) ?? ""
                message += "\n"
                
                var buffer = channel.allocator.buffer(capacity: message.utf8.count)
                buffer.writeString(message)
                try await channel.writeAndFlush(buffer)
                addDebug("Sent message to agent")
                
            } catch {
                connectionError = "Send failed: \(error.localizedDescription)"
                addDebug("Send error: \(error)")
                isWaiting = false
            }
        }
    }
    
    func disconnect() {
        Task {
            try? await tunnelChannel?.close()
            try? await sshClient?.close()
            sshClient = nil
            tunnelChannel = nil
        }
        isConnected = false
        isWaiting = false
        messages = []
        addDebug("Disconnected by user")
    }
    
    private func readAgentResponses() {
        guard let channel = tunnelChannel else { return }
        
        Task {
            do {
                // Add a handler to read incoming data from the agent
                try await channel.pipeline.addHandler(AgentResponseHandler(manager: self))
                addDebug("Agent response handler attached")
            } catch {
                addDebug("Failed to attach response handler: \(error)")
            }
        }
    }
    
    nonisolated func handleAgentData(_ data: String) {
        Task { @MainActor in
            agentBuffer += data
            processAgentBuffer()
        }
    }
    
    private func processAgentBuffer() {
        while agentBuffer.contains("\n") {
            guard let idx = agentBuffer.firstIndex(of: "\n") else { break }
            let line = String(agentBuffer[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            agentBuffer.removeSubrange(...idx)
            
            guard !line.isEmpty else { continue }
            
            do {
                if let data = line.data(using: .utf8),
                   let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let content = json["content"] as? String {
                    isWaiting = false
                    messages.append(ChatMessage(content))
                    addDebug("Received agent response")
                }
            } catch {
                isWaiting = false
                messages.append(ChatMessage(line))
            }
        }
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

// NIO Channel Handler to read agent responses
final class AgentResponseHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    
    private weak var manager: SSHManager?
    
    init(manager: SSHManager) {
        self.manager = manager
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let string = buffer.readString(length: buffer.readableBytes) {
            manager?.handleAgentData(string)
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        Task { @MainActor [weak manager] in
            manager?.addDebug("Channel error: \(error)")
        }
        context.close(promise: nil)
    }
}
