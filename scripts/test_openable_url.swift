import Foundation

enum OpenableURL {
    static func from(_ string: String?) -> URL? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let url = parse(raw) {
            return normalized(url)
        }
        if let detected = firstRawHTTPURL(in: raw), let url = parse(detected) {
            return normalized(url)
        }
        return nil
    }

    static func firstRawHTTPURL(in string: String) -> String? {
        let pattern = #"https?://[^\s<>\"\'\)\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              let swiftRange = Range(match.range, in: string) else {
            return nil
        }
        var found = String(string[swiftRange])
        while let last = found.last, ".,:;!?)]>\"".contains(last) {
            found.removeLast()
        }
        return found
    }

    private static func parse(_ raw: String) -> URL? {
        if let url = URL(string: raw) { return url }
        if let components = URLComponents(string: raw), let url = components.url { return url }
        return nil
    }

    private static func normalized(_ url: URL) -> URL {
        if isAirbnbHost(url), let roomID = airbnbRoomID(from: url) {
            return URL(string: "https://www.airbnb.com/rooms/\(roomID)") ?? url
        }
        return url
    }

    private static func isAirbnbHost(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("airbnb.") || host.contains("abnb.me")
    }

    private static func airbnbRoomID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let roomsIndex = parts.firstIndex(of: "rooms"),
              parts.indices.contains(roomsIndex + 1) else {
            return nil
        }
        let candidate = parts[roomsIndex + 1]
        guard candidate.allSatisfy(\.isNumber), !candidate.isEmpty else { return nil }
        return candidate
    }
}

func expect(_ condition: Bool, _ label: String) {
    if condition { print("PASS \(label)") }
    else { print("FAIL \(label)"); exit(1) }
}

let share = "https://www.airbnb.com/rooms/1711681767125004425?unique_share_id=d056ee0a-c8c7-40c7-aa9f-a343947016ee&viralityEntryPoint=1&s=76"
expect(OpenableURL.from(share)?.absoluteString == "https://www.airbnb.com/rooms/1711681767125004425", "strip tracking")

let blob = """Historic 1974 Trawler on the River
https://www.airbnb.com/rooms/1711681767125004425?unique_share_id=d056ee0a-c8c7-40c7-aa9f-a343947016ee&viralityEntryPoint=1&s=76
"""
expect(OpenableURL.from(blob)?.absoluteString == "https://www.airbnb.com/rooms/1711681767125004425", "extract from title+link paste")

print("All OpenableURL checks passed.")
