import Foundation
import UIKit

enum PageMetadata {
    struct Result {
        var title: String?
        var description: String?
        var image: UIImage?
    }

    private static let safariUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func fetch(from urlString: String) async -> Result {
        guard let url = URL(string: urlString), let scheme = url.scheme, scheme.hasPrefix("http") else {
            return Result()
        }
        do {
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue(safariUA, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            guard !html.isEmpty else { return Result() }

            let title = firstNonEmpty([
                meta(html, property: "og:title"),
                meta(html, name: "twitter:title"),
                jsonLDString(html, key: "name"),
                htmlTitle(html),
            ]).map(clean)

            let description = firstNonEmpty([
                meta(html, property: "og:description"),
                meta(html, name: "twitter:description"),
                meta(html, name: "description"),
            ]).map(clean)

            let imageURLString = firstNonEmpty([
                meta(html, property: "og:image"),
                meta(html, property: "og:image:secure_url"),
                meta(html, name: "twitter:image"),
                jsonLDString(html, key: "image"),
            ])

            var image: UIImage?
            if let imageURLString, let imageURL = resolvedURL(imageURLString, relativeTo: url) {
                image = await downloadImage(imageURL)
            }

            return Result(title: title, description: description, image: image)
        } catch {
            return Result()
        }
    }

    static func isPlaceholderTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return true }
        let placeholders: Set<String> = [
            "shared item",
            "airbnb stay",
            "instagram",
            "x post",
            "facebook",
            "airbnb.com",
            "www.airbnb.com",
            "instagram.com",
            "www.instagram.com",
        ]
        if placeholders.contains(trimmed) { return true }
        if trimmed.hasSuffix(".com") && !trimmed.contains(" ") { return true }
        return false
    }

    private static func downloadImage(_ url: URL) async -> UIImage? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(safariUA, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return UIImage(data: data)
    }

    private static func meta(_ html: String, property: String? = nil, name: String? = nil) -> String? {
        let key = property ?? name ?? ""
        let attribute = property != nil ? "property" : "name"
        let patterns = [
            #"\#(attribute)\s*=\s*["']\#(NSRegularExpression.escapedPattern(for: key))["'][^>]*content\s*=\s*["']([^"']+)["']"#,
            #"content\s*=\s*["']([^"']+)["'][^>]*\#(attribute)\s*=\s*["']\#(NSRegularExpression.escapedPattern(for: key))["']"#,
        ]
        for pattern in patterns {
            if let value = firstMatch(pattern, in: html, group: 1) {
                return decodeHTML(value)
            }
        }
        return nil
    }

    private static func htmlTitle(_ html: String) -> String? {
        guard let raw = firstMatch(#"<title[^>]*>(.*?)</title>"#, in: html, group: 1) else { return nil }
        return decodeHTML(raw)
    }

    private static func jsonLDString(_ html: String, key: String) -> String? {
        guard let block = firstMatch(#"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#, in: html, group: 1) else {
            return nil
        }
        if let quoted = firstMatch(#""\#(key)"\s*:\s*"([^"]+)""#, in: block, group: 1) {
            return decodeHTML(quoted)
        }
        if let nested = firstMatch(#""\#(key)"\s*:\s*\{\s*"url"\s*:\s*"([^"]+)""#, in: block, group: 1) {
            return decodeHTML(nested)
        }
        if let arrayFirst = firstMatch(#""\#(key)"\s*:\s*\[\s*"([^"]+)""#, in: block, group: 1) {
            return decodeHTML(arrayFirst)
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > group,
              let swiftRange = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values.map { $0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }.first { !$0.isEmpty }
    }

    private static func clean(_ value: String) -> String {
        let collapsed = SharedText.normalized(value)
        return collapsed.isEmpty ? value.trimmingCharacters(in: .whitespacesAndNewlines) : collapsed
    }

    private static func decodeHTML(_ value: String) -> String {
        var result = value
        let entities = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&#x27;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    private static func resolvedURL(_ string: String, relativeTo base: URL) -> URL? {
        let trimmed = decodeHTML(string).trimmingCharacters(in: .whitespacesAndNewlines)
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }
}
