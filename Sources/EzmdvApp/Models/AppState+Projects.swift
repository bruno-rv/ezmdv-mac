import AppKit

extension AppState {
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
            updateTabsForRename(oldPath: oldPath, newPath: newPath)
            if let content = contentCache.removeValue(forKey: oldPath) {
                contentCache[newPath] = content
            }
            loadProjectFiles(project)
        } catch {
            lastError = error.localizedDescription
        }
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

    // MARK: - File watching

    func watchProject(_ project: Project) {
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
