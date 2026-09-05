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

        var best = await fetchPage(url)
        if best.image == nil, let embed = instagramEmbedURL(from: url) {
            let extra = await fetchPage(embed)
            if best.title == nil { best.title = extra.title }
            if best.description == nil { best.description = extra.description }
            if best.image == nil { best.image = extra.image }
        }
        return best
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

    static func instagramEmbedURL(from url: URL) -> URL? {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("instagram.com") || host.contains("instagr.am") else { return nil }
        let pattern = #"/(p|reel|reels|tv)/([A-Za-z0-9_-]+)"#
        guard let kindRaw = firstMatch(pattern, in: url.path, group: 1),
              let code = firstMatch(pattern, in: url.path, group: 2),
              !code.isEmpty else {
            return nil
        }
        let kind = kindRaw.lowercased() == "reels" ? "reel" : kindRaw.lowercased()
        return URL(string: "https://www.instagram.com/\(kind)/\(code)/embed/")
    }

    static func imageCandidates(in html: String) -> [String] {
        var found: [String] = []
        func add(_ value: String?) {
            guard let value else { return }
            let trimmed = decodeHTML(value)
                .replacingOccurrences(of: "\\/", with: "/")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !found.contains(trimmed) else { return }
            if looksLikeLogo(trimmed) { return }
            found.append(trimmed)
        }

        add(meta(html, property: "og:image"))
        add(meta(html, property: "og:image:secure_url"))
        add(meta(html, property: "og:image:url"))
        add(meta(html, property: "og:video:poster"))
        add(meta(html, name: "twitter:image"))
        add(meta(html, name: "twitter:image:src"))
        add(meta(html, itemprop: "image"))
        add(jsonLDString(html, key: "image"))
        add(jsonLDString(html, key: "thumbnailUrl"))
        if let href = firstMatch(
            #"<link[^>]+rel\s*=\s*["']image_src["'][^>]+href\s*=\s*["']([^"']+)["']"#,
            in: html,
            group: 1
        ) {
            add(href)
        }
        if let href = firstMatch(
            #"<link[^>]+href\s*=\s*["']([^"']+)["'][^>]+rel\s*=\s*["']image_src["']"#,
            in: html,
            group: 1
        ) {
            add(href)
        }
        if let cdn = firstMatch(
            #"https?://[^"'\\\s]+(?:cdninstagram\.com|fbcdn\.net|scontent)[^"'\\\s]+\.(?:jpe?g|png|webp)"#,
            in: html,
            group: 0
        ) {
            add(cdn)
        }
        return found
    }

    static func downloadImageURL(_ string: String, referer: URL? = nil) async -> UIImage? {
        guard let url = URL(string: string), let scheme = url.scheme, scheme.hasPrefix("http") else {
            return nil
        }
        return await downloadImage(url, referer: referer ?? url)
    }

    private static func fetchPage(_ url: URL) async -> Result {
        do {
            var request = URLRequest(url: url, timeoutInterval: 12)
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

            var image: UIImage?
            for candidate in imageCandidates(in: html) {
                guard let imageURL = resolvedURL(candidate, relativeTo: url) else { continue }
                image = await downloadImage(imageURL, referer: url)
                if image != nil { break }
            }

            return Result(title: title, description: description, image: image)
        } catch {
            return Result()
        }
    }

    private static func downloadImage(_ url: URL, referer: URL) async -> UIImage? {
        do {
            var request = URLRequest(url: url, timeoutInterval: 12)
            request.setValue(safariUA, forHTTPHeaderField: "User-Agent")
            request.setValue("image/avif,image/webp,image/apng,image/jpeg,image/png,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue(cdnReferer(for: url, fallback: referer).absoluteString, forHTTPHeaderField: "Referer")
            let (data, _) = try await URLSession.shared.data(for: request)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private static func cdnReferer(for imageURL: URL, fallback: URL) -> URL {
        let host = imageURL.host?.lowercased() ?? ""
        if host.contains("cdninstagram") || host.contains("fbcdn") || host.contains("scontent") {
            return URL(string: "https://www.instagram.com/") ?? fallback
        }
        return fallback
    }

    private static func looksLikeLogo(_ url: String) -> Bool {
        let lower = url.lowercased()
        if lower.contains("favicon") { return true }
        if lower.contains("apple-touch-icon") { return true }
        if lower.contains("/static/") && (lower.contains("/images/") || lower.contains("/rsrc") || lower.contains("/ico/")) {
            return true
        }
        if lower.contains("logo") && (lower.contains("instagram") || lower.contains("facebook")) {
            return true
        }
        return false
    }

    private static func meta(_ html: String, property: String? = nil, name: String? = nil, itemprop: String? = nil) -> String? {
        let key = property ?? name ?? itemprop ?? ""
        let attribute = property != nil ? "property" : (itemprop != nil ? "itemprop" : "name")
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
        let trimmed = decodeHTML(string)
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }
}
