import Foundation

class AppConfig: ObservableObject {
    @Published var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
        }
    }

    init() {
        self.serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://your-server-ip:8000"
    }

    func resetToDefaults() {
        serverURL = "http://your-server-ip:8000"
    }
}
