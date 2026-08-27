import Foundation

enum SharedText {
    static func normalized(_ string: String) -> String {
        let folded = string
            .decomposedStringWithCompatibilityMapping
            .precomposedStringWithCanonicalMapping
        let halfwidth = folded.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? folded
        let withoutTags = halfwidth.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let withoutIgnorables = String(withoutTags.unicodeScalars.filter { scalar in
            !scalar.properties.isDefaultIgnorableCodePoint
                && scalar.properties.generalCategory != .format
        })
        return withoutIgnorables
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
