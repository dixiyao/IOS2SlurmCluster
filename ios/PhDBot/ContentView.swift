import SwiftUI

struct ContentView: View {
    @State private var sshManager = SSHManager()
    @State private var showChat = false

    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("sshHost") private var sshHost = ""
    @AppStorage("sshUsername") private var sshUsername = ""
    @AppStorage("sshPassword") private var sshPassword = ""

    var body: some View {
        if showChat {
            ChatView(sshManager: sshManager, onDisconnect: {
                sshManager.disconnect()
                showChat = false
            })
        } else {
            ConnectView(
                apiKey: $apiKey,
                sshHost: $sshHost,
                sshUsername: $sshUsername,
                sshPassword: $sshPassword,
                sshManager: sshManager,
                onConnected: { showChat = true }
            )
        }
    }
}
