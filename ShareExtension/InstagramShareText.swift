import Foundation

enum InstagramShareText {
    static func isInstagramURL(_ string: String) -> Bool {
        let lower = string.lowercased()
        if lower.contains("instagram.com") || lower.contains("instagr.am") { return true }
        if let host = URL(string: string)?.host?.lowercased() {
            return host.contains("instagram")
        }
        return false
    }

    static func split(from pieces: [String]) -> (title: String, notes: String) {
        let caption = bestCaption(from: pieces)
        guard !caption.isEmpty else { return ("", "") }
        return splitCaption(caption)
    }

    static func looksLikeComments(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.isEmpty { return false }
        if lower.contains("view all") && lower.contains("comment") { return true }
        if lower.contains("what do you think") { return true }
        if lower.contains("log in to like") { return true }
        if lower.range(of: #"^\d[\d,.]*\s+likes?,?\s+\d"#, options: .regularExpression) != nil {
            return true
        }
        if lower.contains(" likes,") && lower.contains(" comments") { return true }
        let mentions = trimmed.split(whereSeparator: { $0 == "@" }).count - 1
        return mentions >= 3
    }

    private static func bestCaption(from pieces: [String]) -> String {
        let cleaned = pieces
            .map(unwrap)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !looksLikeComments($0) && !isPlaceholder($0) }
        return cleaned.max(by: { $0.count < $1.count }) ?? ""
    }

    private static func unwrap(_ raw: String) -> String {
        let patterns = [
            #"(?i)on instagram:\s*[“"'](.+)[”"']\s*$"#,
            #"(?i)^\d[\d,.]*\s+likes?.*?on instagram:\s*[“"'](.+)[”"']"#,
        ]
        for pattern in patterns {
            if let inner = firstMatch(pattern, in: raw) {
                return inner
            }
        }
        return raw
    }

    private static func isPlaceholder(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["instagram", "instagram.com", "www.instagram.com", "shared item"].contains(trimmed)
    }

    private static func splitCaption(_ caption: String) -> (title: String, notes: String) {
        let unwrapped = unwrap(caption)
        let lines = unwrapped
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !looksLikeComments($0) }

        if lines.count >= 2 {
            return (lines[0], lines.dropFirst().joined(separator: "\n"))
        }

        let text = lines.first ?? unwrapped
        let markers = [
            "Ingredients",
            "Recipe",
            "Instructions",
            "Directions",
            "Method",
            "Serves",
            "For the ",
            "What you need",
            "You'll need",
            "You will need",
        ]
        for marker in markers {
            guard let range = text.range(of: marker, options: .caseInsensitive),
                  range.lowerBound > text.startIndex
            else { continue }
            let title = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = text[range.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if (8...140).contains(title.count) {
                return (title, notes)
            }
        }

        return (text, "")
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[swiftRange])
    }
}
