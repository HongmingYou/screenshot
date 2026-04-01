import SwiftUI

@main
struct ChronicleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(AppSettings.shared)
        }
    }
}
