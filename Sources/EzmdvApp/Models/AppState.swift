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

    // MARK: - Dirty tracking (file content differs from disk)
    @Published var dirtyFiles: Set<String> = []  // Set of file paths with unsaved changes
    private var autoSaveTimers: [String: Timer] = [:]
    private let autoSaveDelay: TimeInterval = 3.0

    // MARK: - Error handling
    @Published var lastError: String? = nil

    // MARK: - File watcher
    private var fileWatcher: FileWatcher?

    enum Pane { case primary, secondary }

    private var statePath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".ezmdv/state-native.json")
    }

    // MARK: - Persistence

    func loadState() {
        guard let data = try? Data(contentsOf: statePath),
              let saved = try? JSONDecoder().decode(SavedState.self, from: data)
        else { return }
        self.projects = saved.projects.map { sp in
            Project(name: sp.name, path: sp.path)
        }
        self.isDarkMode = saved.isDarkMode

        // Load project files so we can restore tabs
        for project in projects {
            loadProjectFiles(project)
            watchProject(project)
            expandedProjectIds.insert(project.id)
        }

        // Restore tabs
        if let savedTabs = saved.tabs {
            for st in savedTabs {
                if let project = projects.first(where: { $0.path == st.projectPath }),
                   FileManager.default.fileExists(atPath: st.filePath) {
                    let tab = FileTab(projectId: project.id, filePath: st.filePath)
                    if !tabs.contains(where: { $0.filePath == st.filePath }) {
                        tabs.append(tab)
                    }
                    loadContent(for: st.filePath)
                    // Restore active tab
                    if st.filePath == saved.activeTabFilePath {
                        primaryTab = tab
                    }
                }
            }
            if primaryTab == nil, let first = tabs.first {
                primaryTab = first
            }
        }
    }

    func saveState() {
        let savedTabs = tabs.compactMap { tab -> SavedTab? in
            guard let project = projects.first(where: { $0.id == tab.projectId }) else { return nil }
            return SavedTab(projectPath: project.path, filePath: tab.filePath)
        }
        let saved = SavedState(
            projects: projects.map { SavedProject(name: $0.name, path: $0.path) },
            isDarkMode: isDarkMode,
            tabs: savedTabs,
            activeTabFilePath: primaryTab?.filePath
        )
        let dir = statePath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: statePath)
        }
    }

    // MARK: - Folder management

    func showOpenFolderDialog() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing markdown files"
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            addProject(at: url.path)
        }
    }

    func addProject(at path: String) {
        guard !projects.contains(where: { $0.path == path }) else {
            // Already exists — just update lastOpened
            if let idx = projects.firstIndex(where: { $0.path == path }) {
                projects[idx].lastOpened = Date()
            }
            return
        }
        let name = (path as NSString).lastPathComponent
        let project = Project(name: name, path: path)
        projects.append(project)
        expandedProjectIds.insert(project.id)
        loadProjectFiles(project)
        watchProject(project)
        saveState()
    }

    func removeProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        tabs.removeAll { $0.projectId == project.id }
        if primaryTab?.projectId == project.id { primaryTab = tabs.first }
        if secondaryTab?.projectId == project.id { secondaryTab = nil }
        saveState()
    }

    func loadProjectFiles(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        let files = FileScanner.scan(directory: project.path)
        projects[idx].files = files
    }

    // MARK: - Tab management

    func openFile(projectId: UUID, filePath: String) {
        let tab = FileTab(projectId: projectId, filePath: filePath)

        // Add to tabs if not already there
        if !tabs.contains(where: { $0.projectId == projectId && $0.filePath == filePath }) {
            tabs.append(tab)
        }
        let existing = tabs.first { $0.projectId == projectId && $0.filePath == filePath }!

        if splitView && secondaryTab == nil {
            secondaryTab = existing
            focusedPane = .secondary
        } else if splitView && focusedPane == .secondary {
            secondaryTab = existing
            focusedPane = .secondary
        } else {
            primaryTab = existing
            focusedPane = .primary
        }

        // Load content
        loadContent(for: filePath)
        saveState()
    }

    func closeTab(_ tab: FileTab) {
        // Auto-save dirty file before closing
        if dirtyFiles.contains(tab.filePath) {
            saveFile(tab.filePath)
        }
        tabs.removeAll { $0 == tab }
        if primaryTab == tab {
            primaryTab = tabs.first
        }
        if secondaryTab == tab {
            secondaryTab = nil
        }
        saveState()
    }

    func loadContent(for filePath: String) {
        guard contentCache[filePath] == nil else { return }
        if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            contentCache[filePath] = content
        }
    }

    func refreshContent(for filePath: String) {
        if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            contentCache[filePath] = content
            dirtyFiles.remove(filePath)
        }
    }

    func markDirty(_ filePath: String) {
        dirtyFiles.insert(filePath)
        scheduleAutoSave(for: filePath)
    }

    func saveFile(_ filePath: String) {
        guard let content = contentCache[filePath] else { return }
        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            dirtyFiles.remove(filePath)
            autoSaveTimers[filePath]?.invalidate()
            autoSaveTimers.removeValue(forKey: filePath)
        } catch {
            lastError = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func scheduleAutoSave(for filePath: String) {
        autoSaveTimers[filePath]?.invalidate()
        autoSaveTimers[filePath] = Timer.scheduledTimer(withTimeInterval: autoSaveDelay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.saveFile(filePath)
            }
        }
    }

    // MARK: - Split view

    func toggleSplitView() {
        if splitView {
            // Exit split
            if focusedPane == .secondary, let sec = secondaryTab {
                primaryTab = sec
            }
            secondaryTab = nil
            splitView = false
            focusedPane = .primary
        } else {
            guard primaryTab != nil else { return }
            splitView = true
            secondaryTab = nil
            focusedPane = .secondary
        }
    }

    func swapPanes() {
        guard splitView else { return }
        let tmp = primaryTab
        primaryTab = secondaryTab
        secondaryTab = tmp
    }

    // MARK: - Theme

    func toggleTheme() {
        isDarkMode.toggle()
        NSApp.appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
        saveState()
    }

    // MARK: - Search

    func performSearch(_ query: String) {
        searchQuery = query
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        searchResults = SearchService.search(query: query, in: projects)
    }

    // MARK: - File operations

    func createNewFile(in project: Project, parentPath: String, name: String) {
        let fileName = name.hasSuffix(".md") ? name : "\(name).md"
        let filePath = (parentPath as NSString).appendingPathComponent(fileName)
        do {
            try FileService.createFile(at: filePath, content: "# \(name.replacingOccurrences(of: ".md", with: ""))\n")
            loadProjectFiles(project)
            openFile(projectId: project.id, filePath: filePath)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func createNewFolder(in project: Project, parentPath: String, name: String) {
        let folderPath = (parentPath as NSString).appendingPathComponent(name)
        do {
            try FileService.createFolder(at: folderPath)
            loadProjectFiles(project)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteFileOrFolder(in project: Project, path: String) {
        do {
            try FileService.delete(at: path)
            // Clean up tabs pointing to this path
            cleanupTabsForDeletedPath(path)
            loadProjectFiles(project)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func renameFileOrFolder(in project: Project, oldPath: String, newName: String) {
        let parentDir = (oldPath as NSString).deletingLastPathComponent
        let newPath = (parentDir as NSString).appendingPathComponent(newName)
        do {
            try FileService.rename(from: oldPath, to: newPath)
            // Update tabs pointing to old path
            updateTabsForRename(oldPath: oldPath, newPath: newPath)
            // Clear old content cache, load new
            if let content = contentCache.removeValue(forKey: oldPath) {
                contentCache[newPath] = content
            }
            loadProjectFiles(project)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func renameProject(_ project: Project, to newName: String) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx].name = newName
        saveState()
    }

    func deleteProjectFromDisk(_ project: Project) {
        do {
            try FileService.delete(at: project.path)
        } catch {
            lastError = error.localizedDescription
            return
        }
        removeProject(project)
    }

    // MARK: - Tab cleanup helpers

    private func cleanupTabsForDeletedPath(_ deletedPath: String) {
        // Remove tabs whose file was deleted (or is inside a deleted folder)
        let affected = tabs.filter { $0.filePath == deletedPath || $0.filePath.hasPrefix(deletedPath + "/") }
        for tab in affected {
            closeTab(tab)
        }
    }

    private func updateTabsForRename(oldPath: String, newPath: String) {
        for i in tabs.indices {
            if tabs[i].filePath == oldPath {
                let newTab = FileTab(projectId: tabs[i].projectId, filePath: newPath)
                if primaryTab == tabs[i] { primaryTab = newTab }
                if secondaryTab == tabs[i] { secondaryTab = newTab }
                tabs[i] = newTab
            } else if tabs[i].filePath.hasPrefix(oldPath + "/") {
                // File inside a renamed folder
                let suffix = String(tabs[i].filePath.dropFirst(oldPath.count))
                let updated = newPath + suffix
                let newTab = FileTab(projectId: tabs[i].projectId, filePath: updated)
                if primaryTab == tabs[i] { primaryTab = newTab }
                if secondaryTab == tabs[i] { secondaryTab = newTab }
                tabs[i] = newTab
            }
        }
    }

    // MARK: - File watching

    private func watchProject(_ project: Project) {
        if fileWatcher == nil {
            fileWatcher = FileWatcher { [weak self] changedPath in
                DispatchQueue.main.async {
                    self?.refreshContent(for: changedPath)
                }
            }
        }
        fileWatcher?.watch(directory: project.path)
    }
}
