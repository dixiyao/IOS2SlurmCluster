import SwiftUI

struct WatchContentView: View {
    @StateObject private var config = WatchConfig()
    @StateObject private var apiService: WatchAPIService

    @State private var dictatedText = ""
    @State private var response = ""
    @State private var showingResponse = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var conversationHistory: [WatchMessage] = []

    init() {
        let config = WatchConfig()
        let apiService = WatchAPIService(config: config)
        _apiService = StateObject(wrappedValue: apiService)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                if conversationHistory.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "waveform")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)

                        Text("Tap to speak")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Button(action: {
                            dictatedText = ""
                        }) {
                            HStack {
                                Image(systemName: "mic.fill")
                                Text("Start")
                            }
                            .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(conversationHistory) { message in
                                WatchMessageBubble(message: message)
                            }
                        }
                    }
                }

                if apiService.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
            .navigationTitle("Slurm Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: WatchSettingsView(config: config)) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showingResponse) {
            ResponseView(response: response)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func sendMessage(_ text: String) {
        let messageText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        let userMessage = WatchMessage(text: messageText, isUser: true)
        conversationHistory.append(userMessage)

        Task {
            do {
                let response = try await apiService.sendPrompt(messageText)

                await MainActor.run {
                    let agentMessage = WatchMessage(text: response, isUser: false)
                    conversationHistory.append(agentMessage)
                    self.response = response
                    showingResponse = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

struct WatchMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp = Date()
}

struct WatchMessageBubble: View {
    let message: WatchMessage

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
            Text(message.text)
                .font(.caption)
                .padding(8)
                .background(message.isUser ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(message.isUser ? .white : .primary)
                .cornerRadius(12)

            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }
}

struct ResponseView: View {
    let response: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                Text(response)
                    .font(.caption)
                    .padding()
            }
            .navigationTitle("Response")
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
}

struct WatchSettingsView: View {
    @ObservedObject var config: WatchConfig
    @State private var serverURL: String

    init(config: WatchConfig) {
        self.config = config
        _serverURL = State(initialValue: config.serverURL)
    }

    var body: some View {
        Form {
            Section(header: Text("Server")) {
                TextField("URL", text: $serverURL)
                    .textInputAutocapitalization(.never)

                Button("Save") {
                    config.serverURL = serverURL
                }
            }

            Section {
                Button("Reset", role: .destructive) {
                    config.resetToDefaults()
                    serverURL = config.serverURL
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    WatchContentView()
}
