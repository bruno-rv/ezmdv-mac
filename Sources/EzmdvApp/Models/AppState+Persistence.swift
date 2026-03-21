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

        for project in projects {
            loadProjectFiles(project)
            watchProject(project)
            expandedProjectIds.insert(project.id)
        }

        if let savedTabs = saved.tabs {
            for st in savedTabs {
                if let project = projects.first(where: { $0.path == st.projectPath }),
                   FileManager.default.fileExists(atPath: st.filePath) {
                    let tab = FileTab(projectId: project.id, filePath: st.filePath)
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
}
