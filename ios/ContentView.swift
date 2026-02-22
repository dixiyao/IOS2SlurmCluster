import SwiftUI

struct ContentView: View {
    @StateObject private var config = AppConfig()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var apiService: APIService

    @State private var textInput = ""
    @State private var response = ""
    @State private var showingSettings = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var conversationHistory: [Message] = []

    init() {
        let config = AppConfig()
        let apiService = APIService(config: config)
        _apiService = StateObject(wrappedValue: apiService)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Conversation history
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(conversationHistory) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                        .onChange(of: conversationHistory.count) { _ in
                            if let lastMessage = conversationHistory.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                Divider()

                // Input area
                VStack(spacing: 12) {
                    // Voice input
                    if speechRecognizer.isAuthorized {
                        HStack {
                            Text(speechRecognizer.transcript.isEmpty ? "Tap microphone to speak" : speechRecognizer.transcript)
                                .foregroundColor(speechRecognizer.transcript.isEmpty ? .gray : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button(action: {
                                if speechRecognizer.isRecording {
                                    speechRecognizer.stopRecording()
                                    textInput = speechRecognizer.transcript
                                } else {
                                    speechRecognizer.resetTranscript()
                                    speechRecognizer.startRecording()
                                }
                            }) {
                                Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                                    .font(.system(size: 24))
                                    .foregroundColor(speechRecognizer.isRecording ? .red : .blue)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }

                    // Text input
                    HStack {
                        TextField("Type your message...", text: $textInput, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .lineLimit(1...5)

                        Button(action: sendMessage) {
                            if apiService.isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(textInput.isEmpty ? .gray : .blue)
                            }
                        }
                        .disabled(textInput.isEmpty || apiService.isLoading)
                    }
                }
                .padding()
            }
            .navigationTitle("Slurm Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: resetConversation) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(config: config)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func sendMessage() {
        let messageText = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        // Add user message to history
        let userMessage = Message(text: messageText, isUser: true)
        conversationHistory.append(userMessage)

        // Clear input
        textInput = ""
        speechRecognizer.resetTranscript()

        // Send to API
        Task {
            do {
                let response = try await apiService.sendPrompt(messageText)

                await MainActor.run {
                    let agentMessage = Message(text: response, isUser: false)
                    conversationHistory.append(agentMessage)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func resetConversation() {
        conversationHistory.removeAll()
        Task {
            do {
                try await apiService.resetConversation()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

struct Message: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp = Date()
}

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isUser { Spacer() }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(12)
                    .background(message.isUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(16)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser { Spacer() }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var config: AppConfig
    @Environment(\.dismiss) var dismiss
    @State private var serverURL: String
    @State private var isTestingConnection = false
    @State private var connectionStatus: String?

    init(config: AppConfig) {
        self.config = config
        _serverURL = State(initialValue: config.serverURL)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Configuration")) {
                    TextField("Server URL", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button(action: testConnection) {
                        HStack {
                            Text("Test Connection")
                            if isTestingConnection {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTestingConnection)

                    if let status = connectionStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(status.contains("Success") ? .green : .red)
                    }
                }

                Section(header: Text("Instructions")) {
                    Text("Enter your server URL in the format: http://your-server-ip:8000")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text("Make sure your server is running and accessible from your device.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Section {
                    Button("Save") {
                        config.serverURL = serverURL
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)

                    Button("Reset to Defaults", role: .destructive) {
                        config.resetToDefaults()
                        serverURL = config.serverURL
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionStatus = nil

        let testConfig = AppConfig()
        testConfig.serverURL = serverURL
        let testService = APIService(config: testConfig)

        Task {
            do {
                let isHealthy = try await testService.checkServerHealth()
                await MainActor.run {
                    connectionStatus = isHealthy ? "Success! Server is reachable." : "Failed to connect to server."
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = "Error: \(error.localizedDescription)"
                    isTestingConnection = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
