import Foundation

/// Subsequence fuzzy matching with a score that favors consecutive runs, word starts and prefixes.
public enum FuzzyMatcher {
    /// Returns nil if `query` is not a subsequence of `candidate` (case-insensitive).
    public static func score(_ query: String, in candidate: String) -> Int? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        if q.isEmpty { return 0 }
        let c = Array(candidate.lowercased())
        let original = Array(candidate)
        var qi = 0
        var score = 0
        var run = 0
        var prevMatch = -2
        for (i, ch) in c.enumerated() where qi < q.count {
            guard ch == q[qi] else {
                run = 0
                continue
            }
            var s = 1
            if i == prevMatch + 1 {
                run += 1
                s += 4 * run
            } else {
                run = 0
            }
            if i == 0 {
                s += 10
            } else {
                let prev = original[i - 1]
                if prev == " " || prev == "/" || prev == "-" || prev == "_" || prev == ":" || prev == "." { s += 8 }
                if original[i].isUppercase && prev.isLowercase { s += 6 }
            }
            score += s
            prevMatch = i
            qi += 1
        }
        guard qi == q.count else { return nil }
        return score * 100 / max(1, c.count / 4 + 1)
    }

    /// Filters and sorts `items` by fuzzy score of `key(item)`.
    public static func rank<T>(_ items: [T], query: String, key: (T) -> String) -> [T] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return items }
        return items.compactMap { item -> (T, Int)? in
            score(query, in: key(item)).map { (item, $0) }
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }
}
