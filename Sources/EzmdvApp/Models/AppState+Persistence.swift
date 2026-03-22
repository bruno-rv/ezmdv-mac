import Foundation

extension AppState {
    func loadState() {
        guard let data = try? Data(contentsOf: statePath),
              let saved = try? JSONDecoder().decode(SavedState.self, from: data)
        else { return }

        self.projects = saved.projects.map { sp in
            Project(name: sp.name, path: sp.path)
        }
        self.isDarkMode = saved.isDarkMode
        self.recentFilePaths = saved.recentFilePaths ?? []

        // Restore sort orders (keyed by project path in saved state)
        if let savedOrders = saved.projectSortOrders {
            for project in projects {
                if let rawValue = savedOrders[project.path],
                   let order = FileSortOrder(rawValue: rawValue) {
                    projectSortOrders[project.id] = order
                }
            }
        }

        for project in projects {
            expandedProjectIds.insert(project.id)
        }
        for project in projects {
            loadProjectFiles(project)
            watchProject(project)
        }

        if let savedTabs = saved.tabs {
            for st in savedTabs {
                if let project = projects.first(where: { $0.path == st.projectPath }),
                   FileManager.default.fileExists(atPath: st.filePath) {
                    let tab = FileTab(projectId: project.id, filePath: st.filePath, isPinned: st.isPinned ?? false)
                    if !tabs.contains(where: { $0.filePath == st.filePath }) {
                        tabs.append(tab)
                    }
                    loadContent(for: st.filePath)
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
            return SavedTab(projectPath: project.path, filePath: tab.filePath, isPinned: tab.isPinned)
        }

        // Encode sort orders as project path → raw value string
        var sortOrdersDict: [String: String] = [:]
        for (projectId, order) in projectSortOrders {
            if let proj = projects.first(where: { $0.id == projectId }) {
                sortOrdersDict[proj.path] = order.rawValue
            }
        }

        let saved = SavedState(
            projects: projects.map { SavedProject(name: $0.name, path: $0.path) },
            isDarkMode: isDarkMode,
            tabs: savedTabs,
            activeTabFilePath: primaryTab?.filePath,
            recentFilePaths: recentFilePaths.isEmpty ? nil : recentFilePaths,
            projectSortOrders: sortOrdersDict.isEmpty ? nil : sortOrdersDict
        )
        let dir = statePath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: statePath)
        }
    }
}
