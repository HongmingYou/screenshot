import Foundation

/// Manages the list of app bundle IDs that must never be captured.
final class PrivacyFilter {
    static let shared = PrivacyFilter()

    // Built-in list — password managers, sensitive system UIs, etc.
    private let defaultBlocklist: Set<String> = [
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.dashlane.dashlane",
        "com.lastpass.lastpass",
        "com.apple.keychainaccess",
        "com.apple.systempreferences",
        "com.apple.loginwindow",
        "com.apple.screensaver.engine",
        "com.apple.SecurityAgent",
    ]

    private var customBlocklist: Set<String> = []

    private init() { loadCustomList() }

    func isBlocked(bundleID: String) -> Bool {
        defaultBlocklist.contains(bundleID) || customBlocklist.contains(bundleID)
    }

    func addToBlocklist(_ bundleID: String) {
        customBlocklist.insert(bundleID)
        saveCustomList()
    }

    func removeFromBlocklist(_ bundleID: String) {
        customBlocklist.remove(bundleID)
        saveCustomList()
    }

    var allCustomEntries: [String] { Array(customBlocklist).sorted() }

    // MARK: - Persistence

    private var customListURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Chronicle/privacy_blocklist.json")
    }

    private func loadCustomList() {
        guard let data = try? Data(contentsOf: customListURL),
              let list = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        customBlocklist = Set(list)
    }

    private func saveCustomList() {
        let data = try? JSONEncoder().encode(Array(customBlocklist))
        try? data?.write(to: customListURL, options: .atomic)
    }
}
