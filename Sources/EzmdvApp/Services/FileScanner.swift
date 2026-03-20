import Foundation

enum FileScanner {
    private static let ignoredDirs: Set<String> = [
        "node_modules", ".git", ".ezmdv", "dist", ".next",
        ".nuxt", ".svelte-kit", "__pycache__", ".venv", "vendor",
    ]

    static func scan(directory path: String) -> [MarkdownFile] {
        let url = URL(fileURLWithPath: path)
        return scanDirectory(url, basePath: path)
    }

    private static func scanDirectory(_ url: URL, basePath: String) -> [MarkdownFile] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [MarkdownFile] = []

        let sorted = contents.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        for item in sorted {
            let name = item.lastPathComponent
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let relative = String(item.path.dropFirst(basePath.count + 1))

            if isDir {
                if ignoredDirs.contains(name) { continue }
                let children = scanDirectory(item, basePath: basePath)
                // Only include directories that contain markdown files
                if !children.isEmpty {
                    files.append(MarkdownFile(
                        name: name, path: item.path,
                        relativePath: relative, isDirectory: true,
                        children: children
                    ))
                }
            } else if name.lowercased().hasSuffix(".md") {
                files.append(MarkdownFile(
                    name: name, path: item.path,
                    relativePath: relative, isDirectory: false
                ))
            }
        }

        // Directories first, then files
        return files.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
