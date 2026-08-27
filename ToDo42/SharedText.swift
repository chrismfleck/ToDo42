import Foundation
import SwiftUI

enum SharedText {
    static let listTitleSize: CGFloat = 16

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

    static func listTitle(_ string: String) -> AttributedString {
        var attributed = AttributedString(normalized(string))
        attributed.font = .system(size: listTitleSize, weight: .semibold, design: .default)
        return attributed
    }
}
