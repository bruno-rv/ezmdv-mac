import Foundation

enum WikiLinkResolver {
    /// The shared regex pattern for matching [[wiki-links]].
    static let pattern = "\\[\\[([^\\[\\]]+)\\]\\]"

    /// A lazily compiled regex for wiki-link matching. Returns nil if pattern is somehow invalid.
    static let regex: NSRegularExpression? = try? NSRegularExpression(pattern: pattern)

    /// Resolves a wiki-link target string to a file within the given file list.
    /// Supports `file`, `file.md`, `path/to/file`, and `file#heading` syntax.
    static func resolve(target: String, in files: [MarkdownFile]) -> MarkdownFile? {
        let flat = MarkdownFile.flatten(files)

        // Strip heading anchor if present
        let fileTarget = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
        let targetLower = fileTarget.lowercased()
        let withExt = targetLower.hasSuffix(".md") ? targetLower : targetLower + ".md"

        // 1. Exact relative path match
        if let match = flat.first(where: { $0.relativePath.lowercased() == withExt }) {
            return match
        }

        // 2. Basename match (unique)
        let basename = (withExt as NSString).lastPathComponent
        let byBasename = flat.filter { $0.name.lowercased() == basename }
        if byBasename.count == 1 { return byBasename[0] }

        // 3. Basename without extension
        let byNameNoExt = flat.filter {
            ($0.name as NSString).deletingPathExtension.lowercased() == targetLower
        }
        if byNameNoExt.count == 1 { return byNameNoExt[0] }

        return nil
    }

    /// Extracts the heading anchor from a wiki-link target (the part after #).
    static func headingAnchor(from target: String) -> String? {
        let parts = target.split(separator: "#", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : nil
    }

    /// Finds all wiki-link matches in content string.
    static func findLinks(in content: String) -> [(fullMatch: NSRange, inner: String)] {
        guard let regex = regex else { return [] }
        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        return matches.compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let inner = nsContent.substring(with: match.range(at: 1))
            return (match.range, inner)
        }
    }
}
