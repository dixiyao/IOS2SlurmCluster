import SwiftUI

struct ChatView: View {
    var wsManager: WebSocketManager
    @State private var speechManager = SpeechManager()
    @State private var inputText = ""
    var onDisconnect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PhDbot")
                        .font(.headline)
                    Text(wsManager.isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(wsManager.isConnected ? .green : .red)
                }
                Spacer()
                Button("Disconnect") { onDisconnect() }
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(wsManager.messages) { msg in
                            MessageBubble(message: msg).id(msg.id)
                        }
                        if wsManager.isWaiting {
                            HStack {
                                Text("Agent is thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: wsManager.messages.count) { _, _ in
                    if let last = wsManager.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button(action: toggleVoice) {
                    Image(systemName: speechManager.isRecording ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundColor(speechManager.isRecording ? .red : .accentColor)
                }
                .disabled(!speechManager.isAvailable)

                TextField("Type a message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit { send() }

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(canSend ? .accentColor : .gray)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .onAppear { speechManager.requestPermission() }
        .onChange(of: speechManager.transcript) { _, text in
            if !text.isEmpty { inputText = text }
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !wsManager.isWaiting
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        wsManager.sendMessage(text)
        inputText = ""
        speechManager.transcript = ""
    }

    private func toggleVoice() {
        if speechManager.isRecording {
            speechManager.stopRecording()
        } else {
            speechManager.transcript = ""
            speechManager.startRecording()
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            if message.isSystem {
                Text(message.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity)
            } else {
                Text(message.text)
                    .padding(10)
                    .background(message.isUser ? Color.accentColor : Color(UIColor.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(12)
            }
            if !message.isUser && !message.isSystem { Spacer() }
        }
    }
}
