#!/usr/bin/env swift
import Foundation

// Lightweight mirror of ToDo42/TikTokShareText.peel for local checks.
enum TikTokShareText {
    static func peel(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        func stripSuffixes(_ suffixes: [String]) {
            for suffix in suffixes where text.lowercased().hasSuffix(suffix.lowercased()) {
                text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return
            }
        }
        func stripPrefixes(_ prefixes: [String]) {
            for prefix in prefixes where text.lowercased().hasPrefix(prefix.lowercased()) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return
            }
        }
        stripSuffixes([
            " on TikTok Search", " on Tiktok Search", " | TikTok Search", " - TikTok Search",
            " · TikTok Search", " – TikTok Search", " — TikTok Search",
        ])
        stripPrefixes([
            "Find ", "find ", "Search ", "search ", "TikTok Search: ", "TikTok Search - ", "TikTok - ", "TikTok: ",
        ])
        for marker in [" on TikTok:", " on Tiktok:", " on TikTok", " on Tiktok"] {
            if let range = text.range(of: marker, options: .caseInsensitive) {
                let after = String(text[range.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines))
                let before = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let afterLower = after.lowercased()
                text = (after.isEmpty || afterLower == "search" || afterLower.hasPrefix("search")) ? before : after
                break
            }
        }
        stripSuffixes([
            " | TikTok", " - TikTok", " · TikTok", " – TikTok", " — TikTok", " on TikTok", " | Tiktok", " - Tiktok",
        ])
        text = text.replacingOccurrences(of: #"(?i)\bTikTok(?:\s+Search)?\b"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders: Set<String> = ["", "tiktok", "tiktok search", "make your day", "tiktok - make your day", "find", "search"]
        if placeholders.contains(text.lowercased()) { return "" }
        return text
    }
}

func expect(_ cond: Bool, _ label: String) {
    if cond { print("OK  \(label)") }
    else { fputs("FAIL \(label)\n", stderr); exit(1) }
}

let samples: [(String, String)] = [
    ("find Asheville cabin on TikTok Search", "Asheville cabin"),
    ("find hot tub on Tiktok Search", "hot tub"),
    ("ChefMaria on TikTok: Best pasta night ever", "Best pasta night ever"),
    ("Cabin tour | TikTok", "Cabin tour"),
    ("TikTok - Make Your Day", ""),
]
for (raw, want) in samples {
    let got = TikTokShareText.peel(raw)
    expect(got == want, "'\(raw)' → '\(got)'")
}
print("All TikTok title peel checks passed.")
