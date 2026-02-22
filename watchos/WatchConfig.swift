import Foundation

class WatchConfig: ObservableObject {
    @Published var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "watchServerURL")
        }
    }

    init() {
        self.serverURL = UserDefaults.standard.string(forKey: "watchServerURL") ?? "http://your-server-ip:8000"
    }

    func resetToDefaults() {
        serverURL = "http://your-server-ip:8000"
    }
}
