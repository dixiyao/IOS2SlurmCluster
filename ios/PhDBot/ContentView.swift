import SwiftUI

struct ContentView: View {
    @State private var wsManager = WebSocketManager()
    @State private var showChat = false

    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("sshHost") private var sshHost = ""
    @AppStorage("sshPort") private var sshPort = "22"
    @AppStorage("sshUsername") private var sshUsername = ""
    @AppStorage("sshPassword") private var sshPassword = ""

    var body: some View {
        if showChat {
            ChatView(wsManager: wsManager, onDisconnect: {
                wsManager.disconnect()
                showChat = false
            })
        } else {
            ConnectView(
                serverURL: $serverURL,
                sshHost: $sshHost,
                sshPort: $sshPort,
                sshUsername: $sshUsername,
                sshPassword: $sshPassword,
                wsManager: wsManager,
                onConnected: { showChat = true }
            )
        }
    }
}
