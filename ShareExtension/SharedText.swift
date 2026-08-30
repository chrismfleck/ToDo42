import Foundation

enum SharedText {
    static func normalized(_ string: String) -> String {
        normalized(string, preserveNewlines: false)
    }

    static func normalizedMultiline(_ string: String) -> String {
        normalized(string, preserveNewlines: true)
    }

    static func reflowNotes(_ string: String) -> String {
        let looksLikeRecipe = string.range(of: "ingredient", options: .caseInsensitive) != nil
            || string.range(of: "tbsp", options: .caseInsensitive) != nil
            || string.range(of: "for the ", options: .caseInsensitive) != nil
        guard looksLikeRecipe else {
            return normalizedMultiline(string)
        }

        var text = string.replacingOccurrences(of: "\r\n", with: "\n")
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
        return normalizedMultiline(text)
    }

    private static func normalized(_ string: String, preserveNewlines: Bool) -> String {
        let mutable = NSMutableString(string: string)
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
            let allowed = CharacterSet(charactersIn: ".,!?'’:-/&()·•|$+")
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
}
