import Foundation

extension AppState {
    func openFile(projectId: UUID, filePath: String) {
        let tab = FileTab(projectId: projectId, filePath: filePath)

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

        loadContent(for: filePath)
        saveState()
    }

    func closeTab(_ tab: FileTab) {
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

    // MARK: - Split view

    func toggleSplitView() {
        if splitView {
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

    // MARK: - Tab cleanup helpers

    func cleanupTabsForDeletedPath(_ deletedPath: String) {
        let affected = tabs.filter { $0.filePath == deletedPath || $0.filePath.hasPrefix(deletedPath + "/") }
        for tab in affected {
            closeTab(tab)
        }
    }

    func updateTabsForRename(oldPath: String, newPath: String) {
        for i in tabs.indices {
            if tabs[i].filePath == oldPath {
                let newTab = FileTab(projectId: tabs[i].projectId, filePath: newPath)
                if primaryTab == tabs[i] { primaryTab = newTab }
                if secondaryTab == tabs[i] { secondaryTab = newTab }
                tabs[i] = newTab
            } else if tabs[i].filePath.hasPrefix(oldPath + "/") {
                let suffix = String(tabs[i].filePath.dropFirst(oldPath.count))
                let updated = newPath + suffix
                let newTab = FileTab(projectId: tabs[i].projectId, filePath: updated)
                if primaryTab == tabs[i] { primaryTab = newTab }
                if secondaryTab == tabs[i] { secondaryTab = newTab }
                tabs[i] = newTab
            }
        }
    }
}
