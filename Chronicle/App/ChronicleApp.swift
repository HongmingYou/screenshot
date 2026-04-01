import SwiftUI

@main
struct ChronicleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu-bar-only app: no windows. Settings scene is required by SwiftUI.
        Settings {
            EmptyView()
        }
    }
}
