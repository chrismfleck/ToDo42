import Foundation

enum InstagramShareText {
    static func isInstagramURL(_ string: String) -> Bool {
        let lower = string.lowercased()
        return lower.contains("instagram.com") || lower.contains("instagr.am")
    }

    static func needsCleanup(title: String, notes: String) -> Bool {
        let t = title.lowercased()
        if t.contains("on instagram") { return true }
        if looksLikeComments(notes) { return true }
        if t.contains("ingredient") || t.contains("for the ") || t.contains("tbsp") { return true }
        if title.contains("&#") || notes.contains("&#") { return true }
        return title.count > 90
    }

    static func refine(title: String, notes: String) -> (title: String, notes: String) {
        let peeled = peelInstagramWrapper(title)
        var nextTitle = peeled.headline
        var leftover = peeled.rest
        var nextNotes = looksLikeComments(notes) ? "" : notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let cut = splitByMarkers(nextTitle)
        nextTitle = cut.title
        leftover = [cut.notes, leftover].filter { !$0.isEmpty }.joined(separator: "\n")

        let titleLines = lines(in: nextTitle)
        if titleLines.count >= 2 {
            nextTitle = titleLines[0]
            leftover = [titleLines.dropFirst().joined(separator: "\n"), leftover]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        if nextNotes.isEmpty {
            nextNotes = leftover
        } else if !leftover.isEmpty, leftover.count > nextNotes.count {
            nextNotes = leftover
        }

        if nextTitle.isEmpty { nextTitle = peeled.headline }
        if !nextNotes.isEmpty {
            nextNotes = SharedText.reflowNotes(nextNotes)
        }
        return (nextTitle.trimmingCharacters(in: .whitespacesAndNewlines), nextNotes)
    }

    static func split(from pieces: [String]) -> (title: String, notes: String) {
        let useful = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !looksLikeComments($0) }
        let longest = useful.max(by: { $0.count < $1.count }) ?? pieces.first ?? ""
        return refine(title: longest, notes: "")
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

    private static func peelInstagramWrapper(_ raw: String) -> (headline: String, rest: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker = text.range(of: "on Instagram:", options: .caseInsensitive) {
            text = String(text[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let marker = text.range(of: "on Instagram", options: .caseInsensitive) {
            var rest = String(text[marker.upperBound...])
            if rest.hasPrefix(":") { rest.removeFirst() }
            text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’")]
        for (open, close) in quotePairs {
            guard text.first == open, let end = text.dropFirst().firstIndex(of: close) else { continue }
            let inside = String(text[text.index(after: text.startIndex)..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(text[text.index(after: end)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if inside.count >= 8 {
                return (inside, after)
            }
        }
        return (text, "")
    }

    private static func lines(in text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !looksLikeComments($0) }
    }

    private static func splitByMarkers(_ text: String) -> (title: String, notes: String) {
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
            let title = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = text[range.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if (8...140).contains(title.count) {
                return (title, notes)
            }
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }
}
