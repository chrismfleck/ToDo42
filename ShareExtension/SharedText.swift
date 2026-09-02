import Foundation

enum SharedText {
    static func normalized(_ string: String) -> String {
        normalized(string, preserveNewlines: false)
    }

    static func normalizedMultiline(_ string: String) -> String {
        normalized(string, preserveNewlines: true)
    }

    static func decodeHTMLEntities(_ string: String) -> String {
        var text = string
        let named: [String: String] = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
            "&bull;": "•",
            "&middot;": "·",
            "&deg;": "°",
            "&frac12;": "1/2",
            "&frac14;": "1/4",
            "&frac34;": "3/4",
            "&ndash;": "-",
            "&mdash;": "-",
            "&hellip;": "...",
        ]
        for _ in 0..<2 {
            for (entity, replacement) in named {
                text = text.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
            }
            text = replaceNumericEntities(in: text, hex: true)
            text = replaceNumericEntities(in: text, hex: false)
        }
        text = text.replacingOccurrences(of: "½", with: "1/2")
        text = text.replacingOccurrences(of: "¼", with: "1/4")
        text = text.replacingOccurrences(of: "¾", with: "3/4")
        return text.replacingOccurrences(
            of: #"&#x?[0-9a-fA-F]+;"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func replaceNumericEntities(in text: String, hex: Bool) -> String {
        let pattern = hex ? #"&#x([0-9a-fA-F]+);"# : #"&#([0-9]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        var result = text
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let digits = ns.substring(with: match.range(at: 1))
            let value = UInt32(digits, radix: hex ? 16 : 10)
            let replacement: String
            if let value, let scalar = Unicode.Scalar(value) {
                replacement = String(Character(scalar))
            } else {
                replacement = ""
            }
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }

    static func reflowNotes(_ string: String) -> String {
        var text = decodeHTMLEntities(string).replacingOccurrences(of: "\r\n", with: "\n")
        let looksLikeRecipe = text.range(of: "ingredient", options: .caseInsensitive) != nil
            || text.range(of: "tbsp", options: .caseInsensitive) != nil
            || text.range(of: "for the ", options: .caseInsensitive) != nil
            || text.contains("•")
        guard looksLikeRecipe else {
            return normalizedMultiline(text)
        }
        let headers = [
            "Ingredients",
            "For the ",
            "Pistachio Herb",
            "Keto Base",
            "Garnish",
            "Instructions",
            "Directions",
            "Method",
            "Serves ",
        ]
        for header in headers {
            let pattern = "(?:^|[ \\n])(?=\(NSRegularExpression.escapedPattern(for: header)))"
            text = text.replacingOccurrences(
                of: pattern,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        text = text.replacingOccurrences(
            of: #"\)\s+(?=[A-Z])"#,
            with: ")\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"[ \n]+(?=\d+(?:/\d+)?\s+(?:tbsp|tsp|cup|cups|oz|lb|g|kg|ml|fillets?|cloves?))\b"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"[ \n]+(?=Salt and\b)"#,
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"\s*[•·]\s*"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"[ \n]+(?=\d+\s+(?:Preheat|Mix|Bake|Add|Season|Serve|Place|Cook|Stir|Remove))"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        return normalizedMultiline(text)
    }

    private static func normalized(_ string: String, preserveNewlines: Bool) -> String {
        let decoded = decodeHTMLEntities(string)
        let mutable = NSMutableString(string: decoded)
        CFStringTransform(mutable, nil, kCFStringTransformFullwidthHalfwidth, false)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)

        var folded = (mutable as String).decomposedStringWithCompatibilityMapping
        folded = folded.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        var output = ""
        output.reserveCapacity(folded.count)
        for scalar in folded.unicodeScalars {
            if scalar.properties.isDefaultIgnorableCodePoint { continue }
            if scalar.properties.generalCategory == .format { continue }
            if scalar.properties.isWhitespace {
                if preserveNewlines, scalar == "\n" || scalar == "\r" {
                    if output.last != "\n" { output.append("\n") }
                } else {
                    output.append(" ")
                }
                continue
            }
            if scalar.properties.isEmoji, scalar.value > 0x7F { continue }
            if scalar.isASCII {
                output.append(Character(scalar))
                continue
            }
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                output.append(Character(scalar))
                continue
            }
            let allowed = CharacterSet(charactersIn: ".,!?'’:-/&()·•|$+°")
            if allowed.contains(scalar) {
                output.append(Character(scalar))
            }
        }
        if preserveNewlines {
            return output
                .replacingOccurrences(of: "[^\\S\\n]+", with: " ", options: .regularExpression)
                .replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return output
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
