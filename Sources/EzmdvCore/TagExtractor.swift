import Foundation

/// Pure tag-extraction logic with no AppKit/SwiftUI/model dependencies.
/// Compiled into EzmdvCore so it can be tested independently of the executable target.
public enum TagExtractor {
    /// Matches `#word` where word starts with a letter and contains [A-Za-z0-9_-].
    /// The `(?<![A-Za-z0-9_])` lookbehind ensures we don't match inside words.
    private static let tagRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])#([A-Za-z][A-Za-z0-9_-]*)"#)
    }()

    /// Returns all unique lowercase tags found in `content`, sorted alphabetically.
    public static func findTags(in content: String) -> [String] {
        let range = NSRange(content.startIndex..., in: content)
        let matches = tagRegex.matches(in: content, range: range)
        var seen = Set<String>()
        for match in matches {
            if let captureRange = Range(match.range(at: 1), in: content) {
                seen.insert(String(content[captureRange]).lowercased())
            }
        }
        return Array(seen).sorted()
    }
}
