import Foundation

enum SearchService {
    static func search(query: String, in projects: [Project],
                       contentFor: ((String) -> String?)? = nil) -> [SearchResult] {
        let lowerQuery = query.lowercased()
        var results: [SearchResult] = []

        for project in projects {
            guard let files = project.files else { continue }
            searchFiles(files, query: lowerQuery, project: project, contentFor: contentFor, results: &results)
        }

        // Sort by match quality: filename match first, then content matches
        return results.sorted { a, b in
            let aNameMatch = a.fileName.lowercased().contains(lowerQuery)
            let bNameMatch = b.fileName.lowercased().contains(lowerQuery)
            if aNameMatch != bNameMatch { return aNameMatch }
            return a.matchCount > b.matchCount
        }
    }

    private static func searchFiles(
        _ files: [MarkdownFile], query: String,
        project: Project, contentFor: ((String) -> String?)? = nil, results: inout [SearchResult]
    ) {
        for file in files {
            if file.isDirectory {
                if let children = file.children {
                    searchFiles(children, query: query, project: project, contentFor: contentFor, results: &results)
                }
                continue
            }

            let nameMatch = file.name.lowercased().contains(query)
            var contentMatchCount = 0
            var preview: String? = nil

            // Search file content
            let fileContent = contentFor?(file.path) ?? (try? String(contentsOfFile: file.path, encoding: .utf8))
            if let content = fileContent {
                let lines = content.components(separatedBy: .newlines)
                for line in lines {
                    if line.lowercased().contains(query) {
                        contentMatchCount += 1
                        if preview == nil {
                            preview = line.trimmingCharacters(in: .whitespaces)
                            if preview!.count > 120 {
                                preview = String(preview!.prefix(120)) + "..."
                            }
                        }
                    }
                }
            }

            if nameMatch || contentMatchCount > 0 {
                results.append(SearchResult(
                    projectId: project.id,
                    projectName: project.name,
                    filePath: file.path,
                    fileName: file.name,
                    preview: preview,
                    matchCount: contentMatchCount
                ))
            }
        }
    }
}
