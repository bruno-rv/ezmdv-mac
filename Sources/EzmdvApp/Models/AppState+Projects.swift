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
        rebuildWikiLinkIndex()
        saveState()
    }

    func loadProjectFiles(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        let files = FileScanner.scan(directory: project.path)
        projects[idx].files = files
        rebuildTagIndex()
        rebuildWikiLinkIndex()
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

    func createNewFile(in project: Project, parentPath: String, name: String, content: String? = nil) {
        let fileName = name.hasSuffix(".md") ? name : "\(name).md"
        let filePath = (parentPath as NSString).appendingPathComponent(fileName)
        let fileContent = content ?? "# \(fileName.replacingOccurrences(of: ".md", with: ""))\n"
        do {
            try FileService.createFile(at: filePath, content: fileContent)
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
            moveCachedContent(from: oldPath, to: newPath)
            let oldBasename = ((oldPath as NSString).lastPathComponent as NSString).deletingPathExtension
            let newBasename = (newName as NSString).deletingPathExtension
            updateWikiLinksForRename(oldBasename: oldBasename, newBasename: newBasename, in: project)
            loadProjectFiles(project)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func updateWikiLinksForRename(oldBasename: String, newBasename: String, in project: Project) {
        let escaped = NSRegularExpression.escapedPattern(for: oldBasename)
        guard let regex = try? NSRegularExpression(
            pattern: "\\[\\[\(escaped)((?:#[^|\\]]+)?)((?:\\|[^\\]]+)?)\\]\\]",
            options: .caseInsensitive
        ) else { return }

        let flat = MarkdownFile.flatten(project.files)
        for file in flat where !file.isDirectory {
            let content = getContent(for: file.path) ?? ""
            let nsContent = content as NSString
            let fullRange = NSRange(location: 0, length: nsContent.length)
            let matches = regex.matches(in: content, range: fullRange)
            guard !matches.isEmpty else { continue }

            var updated = content
            for match in matches.reversed() {
                // Optional groups return NSRange(location: NSNotFound, length: 0) when not matched
                let headingRange = match.range(at: 2)
                let aliasRange   = match.range(at: 3)
                let headingPart  = headingRange.location != NSNotFound ? nsContent.substring(with: headingRange) : ""
                let aliasPart    = aliasRange.location   != NSNotFound ? nsContent.substring(with: aliasRange)   : ""
                let replacement  = "[[\(newBasename)\(headingPart)\(aliasPart)]]"
                if let range = Range(match.range, in: updated) {
                    updated = updated.replacingCharacters(in: range, with: replacement)
                }
            }
            guard updated != content else { continue }
            try? updated.write(toFile: file.path, atomically: true, encoding: .utf8)
            contentCache.set(file.path, updated)
        }
    }

    func moveFileOrFolder(in project: Project, fromPath: String, toFolderPath: String) {
        do {
            let newPath = try FileService.move(from: fromPath, toFolder: toFolderPath)
            updateTabsForRename(oldPath: fromPath, newPath: newPath)
            moveCachedContent(from: fromPath, to: newPath)
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
        searchResults = SearchService.search(query: query, in: projects) { [weak self] path in
            self?.contentCache[path]
        }
    }

    // MARK: - Sort

    func setSortOrder(_ order: FileSortOrder, for project: Project) {
        projectSortOrders[project.id] = order
        saveState()
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
