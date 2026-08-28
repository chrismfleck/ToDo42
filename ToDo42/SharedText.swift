import Foundation

enum SharedText {
    static func normalized(_ string: String) -> String {
        let limited = string.count > 8000 ? String(string.prefix(8000)) : string
        let mutable = NSMutableString(string: limited)
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
                output.append(" ")
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
        return output
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
