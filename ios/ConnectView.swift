import SwiftUI

struct ConnectView: View {
    @Binding var serverURL: String
    @Binding var sshHost: String
    @Binding var sshPort: String
    @Binding var sshUsername: String
    @Binding var sshPassword: String
    var wsManager: WebSocketManager
    var onConnected: () -> Void

    @State private var isConnecting = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Client Server")) {
                    TextField("Server URL", text: $serverURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("SSH Connection")) {
                    TextField("Host", text: $sshHost)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Port", text: $sshPort)
                        .keyboardType(.numberPad)
                    TextField("Username", text: $sshUsername)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("Password", text: $sshPassword)
                }

                if let error = wsManager.connectionError {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
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
                    .disabled(isConnecting || serverURL.isEmpty || sshHost.isEmpty || sshUsername.isEmpty)
                }
            }
            .navigationTitle("PhDbot")
            .onChange(of: wsManager.isConnected) { _, connected in
                if connected {
                    isConnecting = false
                    onConnected()
                }
            }
            .onChange(of: wsManager.connectionError) { _, error in
                if error != nil {
                    isConnecting = false
                }
            }
        }
    }

    private func connect() {
        isConnecting = true
        let ssh: [String: Any] = [
            "host": sshHost,
            "port": Int(sshPort) ?? 22,
            "username": sshUsername,
            "password": sshPassword
        ]
        wsManager.connect(serverURL: serverURL, ssh: ssh)
    }
}
