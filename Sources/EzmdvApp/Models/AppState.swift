import SwiftUI
import AppKit
import EzmdvCore

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

    // MARK: - File content cache (LRU, max 50 entries)
    var contentCache: LRUCache<String, String> = LRUCache(capacity: 50)

    // MARK: - Dirty tracking
    @Published var dirtyFiles: Set<String> = []
    var autoSaveTimers: [String: Timer] = [:]
    let autoSaveDelay: TimeInterval = 3.0

    // MARK: - Error handling
    @Published var lastError: String? = nil

    // MARK: - File watcher
    var fileWatcher: FileWatcher?

    // MARK: - Focus mode
    @Published var isFocusMode: Bool = false

    // MARK: - Recent files (MRU, max 20)
    @Published var recentFilePaths: [String] = []

    // MARK: - Sort orders per project
    @Published var projectSortOrders: [UUID: FileSortOrder] = [:]

    // MARK: - Tags
    @Published var tagIndex: [String: [String]] = [:]
    @Published var activeTagFilter: String? = nil

    // MARK: - Wiki-link index (fast backlinks / orphan detection)
    @Published var wikiLinkIndex: WikiLinkIndex = WikiLinkIndex()

    enum Pane { case primary, secondary }

    enum FileSortOrder: String, CaseIterable {
        case nameAsc, nameDesc, dateModified, size

        var label: String {
            switch self {
            case .nameAsc: return "Name (A–Z)"
            case .nameDesc: return "Name (Z–A)"
            case .dateModified: return "Date Modified"
            case .size: return "Size"
            }
        }
    }

    var statePath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".ezmdv/state-native.json")
    }

    func rebuildTagIndex() {
        let snapshot = projects
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var merged: [String: [String]] = [:]
            for project in snapshot {
                let idx = TagService.buildIndex(for: project)
                for (tag, paths) in idx {
                    merged[tag, default: []].append(contentsOf: paths)
                }
            }
            DispatchQueue.main.async { self?.tagIndex = merged }
        }
    }

    func rebuildWikiLinkIndex() {
        // Snapshot what we need from main-thread state before going to background
        struct FileEntry { let path: String; let name: String; let cached: String? }
        var entries: [FileEntry] = []
        for project in projects {
            let flat = MarkdownFile.flatten(project.files)
            for file in flat where !file.isDirectory {
                let name = (file.name as NSString).deletingPathExtension
                entries.append(FileEntry(path: file.path, name: name, cached: contentCache[file.path]))
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var allFiles: [(path: String, name: String, content: String)] = []
            var newlyCached: [(path: String, content: String)] = []
            for entry in entries {
                let content = entry.cached
                    ?? (try? String(contentsOfFile: entry.path, encoding: .utf8))
                    ?? ""
                if entry.cached == nil && !content.isEmpty {
                    newlyCached.append((entry.path, content))
                }
                allFiles.append((path: entry.path, name: entry.name, content: content))
            }
            let index = WikiLinkIndex.build(files: allFiles)
            DispatchQueue.main.async {
                guard let self else { return }
                for (path, content) in newlyCached {
                    if self.contentCache[path] == nil { self.contentCache.set(path, content) }
                }
                self.wikiLinkIndex = index
            }
        }
    }

    func findFile(at filePath: String) -> (Project, MarkdownFile)? {
        for project in projects {
            guard let files = project.files else { continue }
            if let file = MarkdownFile.flatten(files).first(where: { $0.path == filePath }) {
                return (project, file)
            }
        }
        return nil
    }
}
