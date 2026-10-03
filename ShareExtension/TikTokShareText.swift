import Foundation

/// Cleans TikTok share / search titles such as `find cabin on TikTok Search`
/// or `Creator on TikTok: "caption…"`.
enum TikTokShareText {
    static func isTikTokURL(_ string: String) -> Bool {
        let lower = string.lowercased()
        return lower.contains("tiktok.com")
            || lower.contains("vm.tiktok.com")
            || lower.contains("vt.tiktok.com")
    }

    static func needsCleanup(title: String) -> Bool {
        let t = title.lowercased()
        return t.contains("tiktok")
            || ((t.hasPrefix("find ") || t == "find") && t.contains("search"))
    }

    static func refine(title: String, notes: String) -> (title: String, notes: String) {
        let peeled = peel(title)
        let nextNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = peeled.isEmpty ? title.trimmingCharacters(in: .whitespacesAndNewlines) : peeled
        return SharedText.cutTitle(source, notes: nextNotes)
    }

    static func split(from pieces: [String]) -> (title: String, notes: String) {
        let useful = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isPlaceholder($0) }
        let cleaned = useful.map(peel).filter { !$0.isEmpty && !isPlaceholder($0) }
        let candidates = cleaned.isEmpty ? useful : cleaned
        let longest = candidates.max(by: { $0.count < $1.count }) ?? pieces.first ?? ""
        return refine(title: longest, notes: "")
    }

    static func peel(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // Search chrome: "find … on TikTok Search" → keep the keywords.
        text = stripSuffixes(text, [
            " on TikTok Search",
            " on Tiktok Search",
            " | TikTok Search",
            " - TikTok Search",
            " · TikTok Search",
            " – TikTok Search",
            " — TikTok Search",
        ])

        // Leading Find/Search wrappers from TikTok search / Find Ideas.
        text = stripPrefixes(text, [
            "Find ",
            "find ",
            "Search ",
            "search ",
            "TikTok Search: ",
            "TikTok Search - ",
            "TikTok - ",
            "TikTok: ",
        ])

        // Creator/share wrappers: "Name on TikTok: caption"
        for marker in [" on TikTok:", " on Tiktok:", " on TikTok", " on Tiktok"] {
            if let range = text.range(of: marker, options: .caseInsensitive) {
                let after = String(text[range.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines))
                let before = String(text[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let afterLower = after.lowercased()
                if after.isEmpty || afterLower == "search" || afterLower.hasPrefix("search") {
                    text = before
                } else {
                    text = after
                }
                break
            }
        }

        // Trailing platform labels on video pages.
        text = stripSuffixes(text, [
            " | TikTok",
            " - TikTok",
            " · TikTok",
            " – TikTok",
            " — TikTok",
            " on TikTok",
            " | Tiktok",
            " - Tiktok",
        ])

        // Drop leftover standalone TikTok / TikTok Search mentions.
        text = text.replacingOccurrences(
            of: #"(?i)\bTikTok(?:\s+Search)?\b"#,
            with: " ",
            options: .regularExpression
        )
        text = text
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’")]
        for (open, close) in quotePairs {
            guard text.first == open, text.last == close, text.count >= 3 else { continue }
            text = String(text.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        while text.hasPrefix(":") || text.hasPrefix("-") || text.hasPrefix("|") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while text.hasSuffix(":") || text.hasSuffix("-") || text.hasSuffix("|") {
            text = String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if isPlaceholder(text) { return "" }
        return text
    }

    private static func stripSuffixes(_ text: String, _ suffixes: [String]) -> String {
        var result = text
        for suffix in suffixes {
            if result.lowercased().hasSuffix(suffix.lowercased()) {
                result = String(result.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return result
    }

    private static func stripPrefixes(_ text: String, _ prefixes: [String]) -> String {
        var result = text
        for prefix in prefixes {
            if result.lowercased().hasPrefix(prefix.lowercased()) {
                result = String(result.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return result
    }

    private static func isPlaceholder(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.isEmpty
            || t == "tiktok"
            || t == "tiktok search"
            || t == "make your day"
            || t == "tiktok - make your day"
            || t == "find"
            || t == "search"
    }
}
