import Foundation

enum FacebookShareText {
    static func isFacebookURL(_ string: String) -> Bool {
        let lower = string.lowercased()
        return lower.contains("facebook.com")
            || lower.contains("fb.com")
            || lower.contains("fb.watch")
            || lower.contains("fb.me")
    }

    static func needsCleanup(title: String) -> Bool {
        title.count > 80 || splitTitle(peel(title)) != nil
    }

    static func refine(title: String, notes: String) -> (title: String, notes: String) {
        let source = peel(title)
        guard let cut = splitTitle(source) else {
            return SharedText.cutTitle(source, notes: notes)
        }
        var nextNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if nextNotes.isEmpty {
            nextNotes = cut.rest
        } else if !nextNotes.localizedCaseInsensitiveContains(String(cut.rest.prefix(24))) {
            nextNotes = cut.rest + "\n" + nextNotes
        }
        return SharedText.cutTitle(cut.title, notes: nextNotes)
    }

    static func split(from pieces: [String]) -> (title: String, notes: String) {
        let useful = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let longest = useful.max(by: { $0.count < $1.count }) ?? pieces.first ?? ""
        return refine(title: longest, notes: "")
    }

    private static func peel(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["on Facebook:", "on Facebook"] {
            if let range = text.range(of: marker, options: .caseInsensitive) {
                var rest = String(text[range.upperBound...])
                if rest.hasPrefix(":") { rest.removeFirst() }
                text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        let quotes = CharacterSet(charactersIn: "\"“”'‘’")
        return text.trimmingCharacters(in: quotes.union(.whitespacesAndNewlines))
    }

    private static func splitTitle(_ text: String) -> (title: String, rest: String)? {
        let chars = Array(text)
        for index in chars.indices {
            let char = chars[index]
            guard char == "?" || char == "!" || char == "," || char == "." else { continue }
            if char == ".", index + 1 < chars.endIndex, chars[index + 1].isNumber {
                continue
            }
            let title = String(chars[0...index]).trimmingCharacters(in: .whitespacesAndNewlines)
            let restStart = chars.index(after: index)
            let rest = restStart < chars.endIndex
                ? String(chars[restStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            if title.count >= 12, !rest.isEmpty {
                return (title, rest)
            }
        }
        return nil
    }
}
