import SwiftUI
import AppKit

final class AppState: ObservableObject {
    // MARK: - Projects & Files
    @Published var projects: [Project] = []
    @Published var expandedProjectIds: Set<UUID> = []

    // MARK: - Tabs
    @Published var tabs: [FileTab] = []
    @Published var primaryTab: FileTab? = nil
    @Published var secondaryTab: FileTab? = nil
    @Published var focusedPane: Pane = .primary

    // MARK: - Layout
    @Published var splitView: Bool = false
    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchResult] = []

    // MARK: - Theme
    @Published var isDarkMode: Bool = true

    // MARK: - File content cache
    @Published var contentCache: [String: String] = [:]

    // MARK: - Dirty tracking
    @Published var dirtyFiles: Set<String> = []
    var autoSaveTimers: [String: Timer] = [:]
    let autoSaveDelay: TimeInterval = 3.0

    // MARK: - Error handling
    @Published var lastError: String? = nil

    // MARK: - File watcher
    var fileWatcher: FileWatcher?

    enum Pane { case primary, secondary }

    var statePath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".ezmdv/state-native.json")
    }
}
