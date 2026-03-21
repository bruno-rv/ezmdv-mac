import Foundation

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var lastOpened: Date
    var files: [MarkdownFile]?

    init(name: String, path: String) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.lastOpened = Date()
        self.files = nil
    }
}

struct MarkdownFile: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let relativePath: String
    let isDirectory: Bool
    var children: [MarkdownFile]?

    init(name: String, path: String, relativePath: String, isDirectory: Bool, children: [MarkdownFile]? = nil) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.children = children
    }

    /// Recursively flattens a file tree into a flat array of non-directory files.
    static func flatten(_ files: [MarkdownFile]?) -> [MarkdownFile] {
        guard let files = files else { return [] }
        var result: [MarkdownFile] = []
        for file in files {
            if file.isDirectory {
                result.append(contentsOf: flatten(file.children))
            } else {
                result.append(file)
            }
        }
        return result
    }

    /// Returns flattened files as dictionaries for JS interop.
    static func flattenForJS(_ files: [MarkdownFile]?) -> [[String: String]] {
        flatten(files).map { file in
            ["name": file.name, "path": file.path, "relativePath": file.relativePath]
        }
    }
}
