#!/usr/bin/env swift
import Foundation

// Mirror of ToDo42/XShareText.peel + refine for a quick local check.
enum XShareText {
    static func needsCleanup(title: String) -> Bool {
        let t = title.lowercased()
        return t.contains(" on x:")
            || t.contains(" on x ")
            || t.contains(" on twitter:")
            || t.contains(" on twitter ")
    }

    static func peel(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        let markers = [" on X:", " on X", " on Twitter:", " on Twitter"]
        for marker in markers {
            if let range = text.range(of: marker, options: .caseInsensitive) {
                var rest = String(text[range.upperBound...])
                while rest.first == ":" || rest.first?.isWhitespace == true {
                    rest = String(rest.dropFirst())
                }
                text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

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

func expect(_ cond: Bool, _ label: String) {
    if cond { print("OK  \(label)") }
    else { fputs("FAIL \(label)\n", stderr); exit(1) }
}

let samples: [(String, String)] = [
    (
        "NASA on X: Looking up at the night sky never gets old.",
        "Looking up at the night sky never gets old."
    ),
    (
        "Chris Fleck on X: \"Cabin with a hot tub this weekend?\"",
        "Cabin with a hot tub this weekend?"
    ),
    (
        "x name on X: : Keep the rest of the tweet sentence as the title",
        "Keep the rest of the tweet sentence as the title"
    ),
    (
        "Some User on Twitter: Hello from the timeline",
        "Hello from the timeline"
    ),
]

for (raw, want) in samples {
    let got = XShareText.peel(raw)
    expect(got == want, "'\(raw)' → '\(got)' (want '\(want)')")
}

expect(XShareText.needsCleanup(title: "Name on X: hi"), "needsCleanup on X")
expect(!XShareText.needsCleanup(title: "Cabin weekend plans"), "no cleanup plain title")
print("All X title peel checks passed.")
