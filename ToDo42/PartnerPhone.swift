import Foundation

enum PartnerPhone {
    /// Keep digits and a leading `+` for sms: / Messages.
    static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = ""
        for (index, ch) in trimmed.enumerated() {
            if ch.isNumber {
                out.append(ch)
            } else if ch == "+", index == 0 || out.isEmpty {
                out.append(ch)
            }
        }
        return out
    }
}
