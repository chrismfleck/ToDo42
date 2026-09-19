import Foundation

enum OpenableURL {
    static func from(_ string: String?) -> URL? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let url = parse(raw) {
            return normalized(url)
        }
        return nil
    }

    static func httpsEquivalent(_ url: URL) -> URL? {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme != "http", scheme != "https", scheme != "about" else { return nil }
        if scheme == "airbnb" {
            return airbnbHTTPS(fromDeepLink: url)
        }
        return nil
    }

    private static func parse(_ raw: String) -> URL? {
        if let url = URL(string: raw) { return url }
        if let components = URLComponents(string: raw), let url = components.url { return url }
        if let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let url = URL(string: encoded) {
            return url
        }
        return nil
    }

    private static func normalized(_ url: URL) -> URL {
        if let https = httpsEquivalent(url) {
            return https
        }
        if isAirbnbHost(url), let roomID = airbnbRoomID(from: url) {
            return URL(string: "https://www.airbnb.com/rooms/\(roomID)") ?? url
        }
        return url
    }

    private static func isAirbnbHost(_ url: URL) -> Bool {
        (url.host ?? "").lowercased().contains("airbnb.")
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

    private static func airbnbHTTPS(fromDeepLink url: URL) -> URL? {
        let host = (url.host ?? "").lowercased()
        let pathParts = url.path.split(separator: "/").map(String.init)

        if host == "rooms", let id = pathParts.first, id.allSatisfy(\.isNumber) {
            return URL(string: "https://www.airbnb.com/rooms/\(id)")
        }
        if let id = airbnbRoomID(from: url) {
            return URL(string: "https://www.airbnb.com/rooms/\(id)")
        }
        if !host.isEmpty {
            let path = url.path.isEmpty ? "" : url.path
            return URL(string: "https://www.airbnb.com/\(host)\(path)")
        }
        return URL(string: "https://www.airbnb.com/")
    }
}

func expect(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS \(label)")
    } else {
        print("FAIL \(label)")
        exit(1)
    }
}

let share = "https://www.airbnb.com/rooms/1711681767125004425?unique_share_id=d056ee0a-c8c7-40c7-aa9f-a343947016ee&viralityEntryPoint=1&s=76"
let cleaned = OpenableURL.from(share)?.absoluteString ?? ""
expect(cleaned == "https://www.airbnb.com/rooms/1711681767125004425", "strip airbnb share tracking")

let deep = OpenableURL.from("airbnb://rooms/1711681767125004425")?.absoluteString ?? ""
expect(deep == "https://www.airbnb.com/rooms/1711681767125004425", "airbnb deep link to https")

let other = OpenableURL.from("https://greekseas.com/trips")?.absoluteString ?? ""
expect(other == "https://greekseas.com/trips", "leave non-airbnb urls alone")

expect(OpenableURL.from("   ") == nil, "blank is nil")
expect(OpenableURL.from(nil) == nil, "nil is nil")

print("All OpenableURL checks passed.")
