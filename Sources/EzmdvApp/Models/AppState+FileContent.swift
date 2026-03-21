import Foundation

extension AppState {
    /// Returns cached content or reads from disk (caching the result).
    func getContent(for filePath: String) -> String? {
        if let cached = contentCache[filePath] { return cached }
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return nil }
        contentCache.set(filePath, content)
        return content
    }

    func loadContent(for filePath: String) {
        _ = getContent(for: filePath)
    }

    func moveCachedContent(from oldPath: String, to newPath: String) {
        if let content = contentCache[oldPath] {
            contentCache.remove(oldPath)
            contentCache.set(newPath, content)
        }
    }

    func refreshContent(for filePath: String) {
        if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            contentCache.set(filePath, content)
            dirtyFiles.remove(filePath)
            if filePath.hasSuffix(".md") { rebuildWikiLinkIndex() }
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
            rebuildTagIndex()
            rebuildWikiLinkIndex()
        } catch {
            lastError = "Failed to save: \(error.localizedDescription)"
        }
    }

    func isFileDirty(_ filePath: String) -> Bool {
        dirtyFiles.contains(filePath)
    }

    private func scheduleAutoSave(for filePath: String) {
        autoSaveTimers[filePath]?.invalidate()
        autoSaveTimers[filePath] = Timer.scheduledTimer(withTimeInterval: autoSaveDelay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.saveFile(filePath)
            }
        }
    }
}
