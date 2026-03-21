import Foundation

/// A pure-logic index of wiki-link relationships between markdown files.
/// Supports backlink lookup, outgoing-link lookup, and simple boolean helpers.
public struct WikiLinkIndex {

    /// A single backlink entry: one file that links to a given target.
    public struct BacklinkEntry: Equatable {
        /// Absolute path of the file that contains the link.
        public let sourcePath: String
        /// Basename of the source file without the `.md` extension.
        public let sourceName: String
        /// Raw inner text of the wiki-link, e.g. `"target|display"`.
        public let linkText: String
        /// ~40 characters of surrounding content, with newlines replaced by spaces.
        public let context: String
    }

    // MARK: - Storage

    /// target name (lowercased, no .md ext) → backlink entries
    private var backlinksMap: [String: [BacklinkEntry]] = [:]
    /// source path → target names (lowercased, no .md ext), deduplicated
    private var outgoingMap: [String: [String]] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Build

    /// Builds an index from a collection of (path, name, content) tuples.
    /// `name` should be the basename WITHOUT the `.md` extension.
    public static func build(files: [(path: String, name: String, content: String)]) -> WikiLinkIndex {
        var index = WikiLinkIndex()

        guard let regex = try? NSRegularExpression(pattern: "\\[\\[([^\\[\\]]+)\\]\\]") else {
            return index
        }

        for file in files {
            let content = file.content
            let nsContent = content as NSString
            let fullRange = NSRange(location: 0, length: nsContent.length)
            let matches = regex.matches(in: content, range: fullRange)

            // Track which targets this source has already linked to (for deduplication)
            var seenTargets = Set<String>()

            for match in matches {
                guard match.numberOfRanges >= 2 else { continue }

                // Extract inner text (capture group 1)
                let innerRange = match.range(at: 1)
                guard innerRange.location != NSNotFound else { continue }
                let inner = nsContent.substring(with: innerRange)

                // Normalize: strip alias (after |), strip heading anchor (after #), trim, lowercase, strip .md
                let normalized = normalizeTarget(inner)

                // Build context string (~40 chars before/after the full match)
                let context = extractContext(from: content, nsContent: nsContent, matchRange: match.range)

                let entry = BacklinkEntry(
                    sourcePath: file.path,
                    sourceName: file.name,
                    linkText: inner,
                    context: context
                )

                // Add to backlinksMap (one entry per source+target pair)
                if !seenTargets.contains(normalized) {
                    index.backlinksMap[normalized, default: []].append(entry)
                }

                // Add to outgoingMap (deduplicated)
                if !seenTargets.contains(normalized) {
                    index.outgoingMap[file.path, default: []].append(normalized)
                    seenTargets.insert(normalized)
                }
            }
        }

        return index
    }

    // MARK: - Query

    /// Returns all backlink entries for the given target name.
    /// The input is normalized (lowercased, .md stripped) before lookup.
    public func backlinks(for targetName: String) -> [BacklinkEntry] {
        let key = WikiLinkIndex.normalizeTarget(targetName)
        return backlinksMap[key] ?? []
    }

    /// Returns the list of normalized target names that the given source file links to.
    public func outgoingLinks(from sourcePath: String) -> [String] {
        return outgoingMap[sourcePath] ?? []
    }

    /// Returns `true` if any file links to the given target name.
    public func hasIncoming(_ targetName: String) -> Bool {
        let key = targetName.lowercased().strippingMdSuffix()
        return !(backlinksMap[key]?.isEmpty ?? true)
    }

    /// Returns `true` if the given source file contains any outgoing wiki-links.
    public func hasOutgoing(_ sourcePath: String) -> Bool {
        return !(outgoingMap[sourcePath]?.isEmpty ?? true)
    }

    // MARK: - Helpers

    /// Normalizes a wiki-link target: strip alias, strip heading, trim, lowercase, strip .md suffix.
    private static func normalizeTarget(_ raw: String) -> String {
        var s = raw
        // Strip alias: "target|display" → "target"
        if let pipeIdx = s.firstIndex(of: "|") {
            s = String(s[s.startIndex..<pipeIdx])
        }
        // Strip heading anchor: "target#section" → "target"
        if let hashIdx = s.firstIndex(of: "#") {
            s = String(s[s.startIndex..<hashIdx])
        }
        s = s.trimmingCharacters(in: .whitespaces).lowercased()
        // Strip .md suffix
        return s.strippingMdSuffix()
    }

    /// Extracts up to 40 characters before and after the match range, replacing newlines with spaces.
    private static func extractContext(from content: String, nsContent: NSString, matchRange: NSRange) -> String {
        let totalLength = nsContent.length

        let beforeStart = max(0, matchRange.location - 40)
        let beforeLength = matchRange.location - beforeStart
        let beforeRange = NSRange(location: beforeStart, length: beforeLength)

        let afterLocation = matchRange.location + matchRange.length
        let afterLength = min(40, totalLength - afterLocation)
        let afterRange = NSRange(location: afterLocation, length: afterLength)

        let before = nsContent.substring(with: beforeRange).replacingOccurrences(of: "\n", with: " ")
        let after = nsContent.substring(with: afterRange).replacingOccurrences(of: "\n", with: " ")

        return "…\(before)…\(after)"
    }
}

// MARK: - String helper

private extension String {
    /// Returns the string with a `.md` suffix removed (case-insensitive).
    func strippingMdSuffix() -> String {
        if self.lowercased().hasSuffix(".md") {
            return String(self.dropLast(3))
        }
        return self
    }
}

