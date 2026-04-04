import Foundation

enum FuzzyMatcher: Sendable {
    static func match(query: String, candidates: [String]) -> [String] {
        let q = query.lowercased()
        // 1. Exact match
        let exact = candidates.filter { $0.lowercased() == q }
        if !exact.isEmpty { return exact }
        // 2. Prefix match
        let prefix = candidates.filter { $0.lowercased().hasPrefix(q) }
        if !prefix.isEmpty { return prefix }
        // 3. Contains match
        let contains = candidates.filter { $0.lowercased().contains(q) }
        if !contains.isEmpty { return contains }
        // 4. Fuzzy match (skip for short queries)
        if q.count <= 2 { return [] }
        let threshold = 0.6
        var scored: [(String, Double)] = []
        for candidate in candidates {
            let distance = levenshteinDistance(q, candidate.lowercased())
            let maxLen = max(q.count, candidate.count)
            let similarity = maxLen == 0 ? 1.0 : 1.0 - Double(distance) / Double(maxLen)
            if similarity >= threshold { scored.append((candidate, similarity)) }
        }
        scored.sort { $0.1 > $1.1 }
        return scored.map { $0.0 }
    }

    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1), b = Array(s2)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j-1] + 1, prev[j-1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }
}
