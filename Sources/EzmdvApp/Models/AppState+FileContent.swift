import Foundation

extension AppState {
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
