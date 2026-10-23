import SwiftUI

final class IOSSettings: ServerConfig {
    static let shared = IOSSettings()

    private init() {
        super.init()
        Self.log("settings loaded: server=\(serverURL.isEmpty ? "(none)" : serverURL) token=\(token.isEmpty ? "none" : "set")")
    }
}

@main
struct SparkTopIOSApp: App {
    @StateObject private var settings = IOSSettings.shared
    @StateObject private var store = SnapshotStore(settings: IOSSettings.shared)

    var body: some Scene {
        WindowGroup {
            RootView(store: store, settings: settings)
        }
    }
}
