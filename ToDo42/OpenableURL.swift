import Foundation
import UIKit

/// Turns saved / shared links into URLs that open reliably from Save 4 Two.
///
/// Some Airbnb share links (especially ones with `viralityEntryPoint`) fail when
/// iOS hands them to the Airbnb app. Stripping to `https://www.airbnb.com/rooms/{id}`
/// makes them open like every other Airbnb listing.
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

    static func open(_ string: String?) {
        guard let url = from(string) else { return }
        UIApplication.shared.open(url)
    }

    static func open(_ url: URL) {
        UIApplication.shared.open(normalized(url))
    }

    /// Convert custom schemes (e.g. `airbnb://rooms/123`) to https pages.
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
