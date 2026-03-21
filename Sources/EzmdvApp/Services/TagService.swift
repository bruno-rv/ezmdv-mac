import Foundation
import EzmdvCore

enum TagService {
    /// Returns all unique lowercase tags found in `content`.
    static func findTags(in content: String) -> [String] {
        TagExtractor.findTags(in: content)
    }

    /// Builds a tag → [absolute file paths] index for a project.
    static func buildIndex(for project: Project) -> [String: [String]] {
        let flatFiles = MarkdownFile.flatten(project.files)
        var index: [String: [String]] = [:]
        for file in flatFiles where !file.isDirectory {
            guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else { continue }
            for tag in TagExtractor.findTags(in: content) {
                index[tag, default: []].append(file.path)
            }
        }
        return index
    }
}
