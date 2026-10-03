import Foundation

/// Cleans X / Twitter share titles like `Display Name on X: "Tweet text…"`.
enum XShareText {
    static func isXURL(_ string: String) -> Bool {
        let lower = string.lowercased()
        return lower.contains("x.com")
            || lower.contains("twitter.com")
            || lower.contains("mobile.twitter.com")
            || lower.hasPrefix("https://t.co/")
            || lower.hasPrefix("http://t.co/")
    }

    static func needsCleanup(title: String) -> Bool {
        let t = title.lowercased()
        return t.contains(" on x:")
            || t.contains(" on x ")
            || t.contains(" on twitter:")
            || t.contains(" on twitter ")
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
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("log in") }
        // Prefer a piece that already looks like tweet body (no "on X:" wrapper).
        let withoutWrapper = useful.filter { !needsCleanup(title: $0) }
        let candidates = withoutWrapper.isEmpty ? useful : withoutWrapper + useful
        let longest = candidates.max(by: { $0.count < $1.count }) ?? pieces.first ?? ""
        return refine(title: longest, notes: "")
    }

    /// Drops `Name on X:` / `Name on Twitter:` and surrounding quotes.
    static func peel(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        let markers = [" on X:", " on X", " on Twitter:", " on Twitter"]
        for marker in markers {
            if let range = text.range(of: marker, options: .caseInsensitive) {
                var rest = String(text[range.upperBound...])
                // Handle `on X: : tweet` or leftover colons after the marker.
                while rest.first == ":" || rest.first?.isWhitespace == true {
                    rest = String(rest.dropFirst())
                }
                text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Strip wrapping quotes X often puts around the tweet body.
        let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’")]
        for (open, close) in quotePairs {
            guard text.first == open else { continue }
            if text.last == close, text.count >= 3 {
                text = String(text.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            if let end = text.dropFirst().firstIndex(of: close) {
                let inside = String(text[text.index(after: text.startIndex)..<end])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if inside.count >= 8 {
                    text = inside
                    break
                }
            }
        }

        while text.hasPrefix(":") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
