import Foundation

enum InstagramShareText {
    static func isInstagramURL(_ string: String) -> Bool {
        let lower = string.lowercased()
        return lower.contains("instagram.com") || lower.contains("instagr.am") || lower.contains("instagram")
    }

    static func needsCleanup(title: String, notes: String) -> Bool {
        title.lowercased().contains("on instagram") || looksLikeComments(notes)
    }

    static func refine(title: String, notes: String) -> (title: String, notes: String) {
        var nextTitle = unwrap(title)
        var nextNotes = looksLikeComments(notes) ? "" : notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let cut = splitByMarkers(nextTitle)
        if !cut.notes.isEmpty {
            nextTitle = cut.title
            if nextNotes.isEmpty { nextNotes = cut.notes }
        }

        let titleLines = lines(in: nextTitle)
        if titleLines.count >= 2 {
            nextTitle = unwrap(titleLines[0])
            let rest = titleLines.dropFirst().joined(separator: "\n")
            if nextNotes.isEmpty { nextNotes = rest }
        }

        nextTitle = unwrap(nextTitle)
        if nextTitle.isEmpty { nextTitle = unwrap(title) }
        if !nextNotes.isEmpty {
            nextNotes = SharedText.reflowNotes(nextNotes)
        }
        return (nextTitle, nextNotes)
    }

    static func split(from pieces: [String]) -> (title: String, notes: String) {
        refine(title: pieces.first ?? "", notes: pieces.dropFirst().joined(separator: "\n"))
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

    static func unwrap(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker = text.range(of: "on Instagram:", options: .caseInsensitive) {
            text = String(text[marker.upperBound...])
        } else if let marker = text.range(of: "on Instagram", options: .caseInsensitive) {
            var rest = String(text[marker.upperBound...])
            if rest.hasPrefix(":") { rest.removeFirst() }
            text = rest
        }
        let quotes = CharacterSet(charactersIn: "\"“”'‘’")
        text = text.trimmingCharacters(in: quotes.union(.whitespacesAndNewlines))
        if let endQuote = text.firstIndex(of: "\""), endQuote < text.endIndex {
            let before = text[..<endQuote].trimmingCharacters(in: quotes.union(.whitespacesAndNewlines))
            if (8...140).contains(before.count) {
                return String(before)
            }
        }
        return text
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
            let title = unwrap(String(text[..<range.lowerBound]))
            let notes = text[range.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if (8...140).contains(title.count) {
                return (title, notes)
            }
        }
        return (unwrap(text), "")
    }
}
