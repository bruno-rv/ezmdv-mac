import Foundation

enum FuzzyMatcher {
    /// Scores how well `query` fuzzy-matches `target`. Returns 0 for no match.
    /// Higher scores indicate better matches: exact > substring > fuzzy character match.
    static func score(query: String, target: String) -> Int {
        if query.isEmpty { return 1 }
        if target.contains(query) { return 100 + (target.count == query.count ? 50 : 0) }

        var score = 0
        var tIdx = target.startIndex
        var consecutive = 0

        for qChar in query {
            var found = false
            while tIdx < target.endIndex {
                if target[tIdx] == qChar {
                    score += 10
                    // Word boundary bonus
                    if tIdx == target.startIndex || !target[target.index(before: tIdx)].isLetter {
                        score += 8
                    }
                    consecutive += 1
                    if consecutive > 1 { score += 5 }
                    tIdx = target.index(after: tIdx)
                    found = true
                    break
                }
                consecutive = 0
                tIdx = target.index(after: tIdx)
            }
            if !found { return 0 }
        }
        return score
    }
}
