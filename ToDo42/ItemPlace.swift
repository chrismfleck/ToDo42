import Foundation
import CoreLocation

enum ItemPlace {
    struct Fix: Equatable {
        var latitude: Double
        var longitude: Double
        var locality: String?
    }

    static func coordinates(in text: String) -> (Double, Double)? {
        let decoded = text.removingPercentEncoding ?? text
        let patterns = [
            #"[?&](?:ll|sll|center|q|query)=(-?\d{1,2}\.\d{3,}),\s*(-?\d{1,3}\.\d{3,})"#,
            #"@(-?\d{1,2}\.\d{3,}),\s*(-?\d{1,3}\.\d{3,})"#,
            #"!3d(-?\d{1,2}\.\d{3,})!4d(-?\d{1,3}\.\d{3,})"#,
            #""(?:lat|latitude|listingLat)"\s*:\s*(-?\d{1,2}\.\d{3,}).{0,80}"(?:lng|lon|longitude|listingLng)"\s*:\s*(-?\d{1,3}\.\d{3,})"#,
            #""(?:lng|lon|longitude|listingLng)"\s*:\s*(-?\d{1,3}\.\d{3,}).{0,80}"(?:lat|latitude|listingLat)"\s*:\s*(-?\d{1,2}\.\d{3,})"#,
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let match = firstMatch(pattern, in: decoded) else { continue }
            let first = Double(match.0)
            let second = Double(match.1)
            guard let first, let second else { continue }
            let pair = index == 4 ? (second, first) : (first, second)
            if isValidCoordinate(lat: pair.0, lon: pair.1) {
                return pair
            }
        }
        return nil
    }

    static func isValidCoordinate(lat: Double, lon: Double) -> Bool {
        abs(lat) <= 90 && abs(lon) <= 180 && !(abs(lat) < 0.01 && abs(lon) < 0.01)
    }

    static func locality(from html: String) -> String? {
        let patterns = [
            #""localizedCityName"\s*:\s*"([^"]+)""#,
            #""city"\s*:\s*"([A-Za-z][^"]{1,40})""#,
            #"<meta[^>]+property=["']og:locality["'][^>]+content=["']([^"]+)["']"#,
        ]
        for pattern in patterns {
            if let name = firstGroup(pattern, in: html) {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 2, trimmed.count <= 40, !trimmed.contains("\\") {
                    return trimmed
                }
            }
        }
        return nil
    }

    static func miles(from origin: CLLocation, to latitude: Double, longitude: Double) -> Double {
        origin.distance(from: CLLocation(latitude: latitude, longitude: longitude)) / 1609.344
    }

    static func formattedMiles(_ miles: Double) -> String {
        if miles < 0.05 { return "nearby" }
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }
        return "\(Int(miles.rounded())) mi"
    }

    static func line(locality: String?, miles: Double?) -> String? {
        let city = locality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !city.isEmpty, let miles {
            return "\(city) · \(formattedMiles(miles))"
        }
        if !city.isEmpty { return city }
        if let miles { return formattedMiles(miles) }
        return nil
    }

    static func resolve(urlString: String?, title: String, cached: Fix?, cacheKey: String?) async -> Fix? {
        let key = cacheKey ?? ""
        if let cached, !key.isEmpty { return cached }
        let haystack = [urlString ?? "", title].joined(separator: "\n")
        var coords = coordinates(in: haystack)
        var locality: String?
        if coords == nil, let urlString, let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
            if let page = await fetchHTML(url) {
                coords = coordinates(in: page)
                locality = Self.locality(from: page)
            }
        }
        if coords == nil, let mapsQuery = mapsQueryAddress(urlString) {
            if let fix = await geocode(mapsQuery) {
                return fix
            }
        }
        guard let coords else { return nil }
        if locality == nil {
            locality = await reverseLocality(lat: coords.0, lon: coords.1)
        }
        return Fix(latitude: coords.0, longitude: coords.1, locality: locality)
    }

    private static func mapsQueryAddress(_ urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        let host = url.host?.lowercased() ?? ""
        guard host.contains("maps.apple") || host.contains("google.com") || host.contains("maps.google") else {
            return nil
        }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        for name in ["q", "query", "address"] {
            if let value = items.first(where: { $0.name == name })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty,
               coordinates(in: value) == nil {
                return value
            }
        }
        return nil
    }

    private static func fetchHTML(_ url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        } catch {
            return nil
        }
    }

    private static func reverseLocality(lat: Double, lon: Double) async -> String? {
        let location = CLLocation(latitude: lat, longitude: lon)
        let marks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return placeLabel(marks?.first)
    }

    private static func geocode(_ address: String) async -> Fix? {
        let marks = try? await CLGeocoder().geocodeAddressString(address)
        guard let mark = marks?.first, let loc = mark.location else { return nil }
        return Fix(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            locality: placeLabel(mark)
        )
    }

    static func placeLabel(_ mark: CLPlacemark?) -> String? {
        let city = mark?.locality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !city.isEmpty { return city }
        let town = mark?.subAdministrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !town.isEmpty { return town }
        let name = mark?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let r1 = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r1])
    }

    private static func firstMatch(_ pattern: String, in text: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 3,
              let r1 = Range(match.range(at: 1), in: text),
              let r2 = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[r1]), String(text[r2]))
    }
}
