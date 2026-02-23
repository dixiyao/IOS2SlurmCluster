import SwiftUI

struct ConnectView: View {
    @Binding var apiKey: String
    @Binding var sshHost: String
    @Binding var sshUsername: String
    @Binding var sshPassword: String
    var sshManager: SSHManager
    var onConnected: () -> Void

    @State private var isConnecting = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API Key")) {
                    SecureField("Gemini API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(header: Text("SSH Server (Port 22)")) {
                    TextField("Server Host", text: $sshHost)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $sshUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $sshPassword)
                    Text("Direct SSH to your cluster (e.g., fe02.ds.uchicago.edu)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let error = sshManager.connectionError {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                if !sshManager.debugLogs.isEmpty {
                    Section(header: Text("Debug")) {
                        ForEach(Array(sshManager.debugLogs.suffix(8).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Button(action: connect) {
                        HStack {
                            Spacer()
                            if isConnecting {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Connecting...")
                            } else {
                                Text("Connect")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isConnecting || apiKey.isEmpty || sshHost.isEmpty || sshUsername.isEmpty)
                }
            }
            .navigationTitle("PhDbot")
            .onChange(of: sshManager.isConnected) { _, connected in
                if connected {
                    isConnecting = false
                    onConnected()
                }
            }
            .onChange(of: sshManager.connectionError) { _, error in
                if error != nil {
                    isConnecting = false
                }
            }
        }
    }

    private func connect() {
        isConnecting = true
        let normalizedHost = normalizeHost(sshHost)
        sshManager.connect(
            host: normalizedHost,
            port: 22,
            username: sshUsername,
            password: sshPassword,
            apiKey: apiKey
        )
    }

    private func normalizeHost(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return host
        }

        let withoutScheme = trimmed
            .replacingOccurrences(of: "ssh://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")

        if let firstPart = withoutScheme.split(separator: "/").first {
            let hostPort = String(firstPart)
            if let colonIndex = hostPort.firstIndex(of: ":") {
                return String(hostPort[..<colonIndex])
            }
            return hostPort
        }

        return trimmed
    }
}
