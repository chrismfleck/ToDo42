import Foundation

enum TitleCut {
    static let maxTitleLength = 80

    static func cutTitle(_ title: String, notes: String) -> (title: String, notes: String) {
        let source = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return (source, existingNotes) }

        let chars = Array(source)
        let window = min(maxTitleLength, chars.count)
        var punctIndex: Int?
        for index in 0..<window {
            let char = chars[index]
            guard char == "," || char == "." || char == "?" || char == "!" else { continue }
            if char == ".", isDecimalOrEllipsis(chars, index) { continue }
            let length = index + 1
            if length < 8 { continue }
            if char == ",", length < 12 { continue }
            punctIndex = index
            break
        }

        let endIndex: Int
        if let punctIndex {
            endIndex = punctIndex
        } else if chars.count > maxTitleLength {
            let last = maxTitleLength - 1
            if let space = stride(from: last, through: 24, by: -1).first(where: { chars[$0] == " " }) {
                endIndex = space - 1
            } else {
                endIndex = last
            }
        } else {
            return (source, existingNotes)
        }

        let nextTitle = String(chars[0...endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = endIndex + 1 < chars.count
            ? String(chars[(endIndex + 1)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        guard !nextTitle.isEmpty else { return (source, existingNotes) }

        var nextNotes = existingNotes
        if !rest.isEmpty {
            if nextNotes.isEmpty {
                nextNotes = rest
            } else if !nextNotes.localizedCaseInsensitiveContains(String(rest.prefix(24))) {
                nextNotes = rest + "\n" + nextNotes
            }
        }
        return (nextTitle, nextNotes)
    }

    private static func isDecimalOrEllipsis(_ chars: [Character], _ index: Int) -> Bool {
        let next = index + 1 < chars.endIndex ? chars[index + 1] : nil
        if let next, next.isNumber { return true }
        let prev = index > 0 ? chars[index - 1] : nil
        if prev == "." || next == "." { return true }
        if prev == " ", next == " " || next == "." { return true }
        if next == " ", index + 2 < chars.endIndex, chars[index + 2] == "." { return true }
        return false
    }
}

var failed = 0
func expect(_ condition: Bool, _ name: String) {
    if condition { print("PASS \(name)") }
    else { failed += 1; print("FAIL \(name)") }
}

let panhandle = "Don't skip these spots in the Panhandle! Comment MAP' and I'll send you my Florida interactive map with 800+ beaches, springs, restaurants, cool things to do, and hidden gems."
let cut = TitleCut.cutTitle(panhandle, notes: "")
expect(cut.title == "Don't skip these spots in the Panhandle!", "Splits at the first exclamation point")
expect(cut.notes.hasPrefix("Comment MAP'"), "Remainder goes into notes")
expect(cut.title.count <= 80, "Title stays at or under 80 characters")

let noPunct = String(repeating: "abcdefghij ", count: 12)
let capped = TitleCut.cutTitle(noPunct, notes: "")
expect(capped.title.count <= 80, "No punctuation caps at 80")
expect(!capped.notes.isEmpty, "Overflow without punctuation goes to notes")

let short = TitleCut.cutTitle("Lake House", notes: "Weekend getaway")
expect(short.title == "Lake House", "Short titles are unchanged")
expect(short.notes == "Weekend getaway", "Short titles keep existing notes")

if failed > 0 {
    fputs("\(failed) test(s) failed\n", stderr)
    exit(1)
}
print("All tests passed")
