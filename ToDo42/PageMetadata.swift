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

        var best = Result()
        if isTikTokURL(url.absoluteString) {
            best = await fetchTikTokOEmbed(url)
        }
        if best.image == nil || best.title == nil {
            let page = await fetchPage(url)
            if best.title == nil { best.title = page.title }
            if best.description == nil { best.description = page.description }
            if best.image == nil { best.image = page.image }
        }
        if best.image == nil, let embed = instagramEmbedURL(from: url) {
            let extra = await fetchPage(embed)
            if best.title == nil { best.title = extra.title }
            if best.description == nil { best.description = extra.description }
            if best.image == nil { best.image = extra.image }
        }
        return best
    }

    static func isTikTokURL(_ string: String) -> Bool {
        string.lowercased().contains("tiktok.com")
    }

    static func oembedURL(for pageURL: URL) -> URL? {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.tiktok.com"
        comps.path = "/oembed"
        comps.queryItems = [URLQueryItem(name: "url", value: pageURL.absoluteString)]
        return comps.url
    }

    static func isPlaceholderTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return true }
        let placeholders: Set<String> = [
            "shared item",
            "airbnb stay",
            "instagram",
            "tiktok",
            "x post",
            "facebook",
            "airbnb.com",
            "www.airbnb.com",
            "instagram.com",
            "www.instagram.com",
            "tiktok.com",
            "www.tiktok.com",
            "vm.tiktok.com",
            "vt.tiktok.com",
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
            var trimmed = decodeHTML(value)
                .replacingOccurrences(of: "\\/", with: "/")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if looksLikeLogo(trimmed) { return }
            // X serves og/card images as webp; request JPEG so UIImage always decodes.
            if isTwitterImageCDN(trimmed) {
                trimmed = preferredTwitterMediaURL(trimmed)
            }
            guard !found.contains(trimmed) else { return }
            found.append(trimmed)
        }

        // X/Twitter: prefer real post media over the generic SSR og:image card.
        for media in twitterMediaURLs(in: html) {
            add(media)
        }
        for thumb in twitterVideoThumbURLs(in: html) {
            add(thumb)
        }
        for card in twitterCardImageURLs(in: html) {
            add(card)
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
        if let cover = firstMatch(
            #""(?:originCover|dynamicCover|cover|thumbnail_url)"\s*:\s*"(https?://[^"]+)"#,
            in: html,
            group: 1
        ) {
            add(cover)
        }
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
        if let image = await downloadImageOnce(url, referer: referer) {
            return image
        }
        // Link-preview cards and og images are often webp; retry as JPEG if decode fails.
        let raw = url.absoluteString
        if isTwitterImageCDN(raw) {
            let jpegURLString = preferredTwitterMediaURL(raw)
            if jpegURLString != raw, let jpegURL = URL(string: jpegURLString) {
                return await downloadImageOnce(jpegURL, referer: referer)
            }
        }
        return nil
    }

    private static func downloadImageOnce(_ url: URL, referer: URL) async -> UIImage? {
        do {
            var request = URLRequest(url: url, timeoutInterval: 12)
            request.setValue(safariUA, forHTTPHeaderField: "User-Agent")
            request.setValue("image/jpeg,image/png,image/webp,image/apng,image/avif,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue(cdnReferer(for: url, fallback: referer).absoluteString, forHTTPHeaderField: "Referer")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            // Reject HTML error pages masquerading as image bytes.
            if data.count >= 15, let head = String(data: data.prefix(64), encoding: .utf8)?.lowercased(),
               head.contains("<html") || head.contains("<!doctype") {
                return nil
            }
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
        if host.contains("tiktokcdn") || host.contains("muscdn") || host.contains("tiktok.com") {
            return URL(string: "https://www.tiktok.com/") ?? fallback
        }
        if host.contains("twimg.com") || host.contains("pscp.tv") {
            return URL(string: "https://x.com/") ?? fallback
        }
        return fallback
    }

    private static func looksLikeLogo(_ url: String) -> Bool {
        let lower = url.lowercased()
        if lower.contains("favicon") { return true }
        if lower.contains("apple-touch-icon") { return true }
        // X often sets og:image to a generic SSR card, not the post media.
        if lower.contains("abs.twimg.com") { return true }
        if lower.contains("/rweb/") && lower.contains("/og/image") { return true }
        if lower.contains("/static/") && (lower.contains("/images/") || lower.contains("/rsrc") || lower.contains("/ico/")) {
            return true
        }
        if lower.contains("logo") && (lower.contains("instagram") || lower.contains("facebook") || lower.contains("tiktok") || lower.contains("twitter") || lower.contains("x.com")) {
            return true
        }
        if (lower.contains("tiktokcdn") || lower.contains("muscdn"))
            && (lower.contains("static") || lower.contains(".js") || lower.contains(".css") || lower.contains("obj/tiktok-web")) {
            return true
        }
        return false
    }

    /// Post photos on X live under pbs.twimg.com/media/…, not the default og:image.
    private static func twitterMediaURLs(in html: String) -> [String] {
        uniqueMatches(
            #"https?://pbs\.twimg\.com/media/[A-Za-z0-9_-]+(?:\.(?:jpe?g|png|webp))?(?:\?[^"'\\\s]*)?"#,
            in: html
        )
    }

    /// Link-preview posts (summary_large_image) use card_img instead of /media/.
    private static func twitterCardImageURLs(in html: String) -> [String] {
        uniqueMatches(
            #"https?://pbs\.twimg\.com/card_img/[0-9]+/[A-Za-z0-9_-]+(?:\?[^"'\\\s]*)?"#,
            in: html
        )
    }

    /// Video posts often only expose amplify / ext_tw thumbs.
    private static func twitterVideoThumbURLs(in html: String) -> [String] {
        uniqueMatches(
            #"https?://pbs\.twimg\.com/(?:amplify_video_thumb|ext_tw_video_thumb|tweet_video_thumb)/[0-9]+/img/[A-Za-z0-9_-]+(?:\.(?:jpe?g|png|webp))?(?:\?[^"'\\\s]*)?"#,
            in: html
        )
    }

    private static func uniqueMatches(_ pattern: String, in html: String) -> [String] {
        let normalized = html.replacingOccurrences(of: "\\/", with: "/")
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        var urls: [String] = []
        for match in regex.matches(in: normalized, options: [], range: range) {
            guard let swiftRange = Range(match.range, in: normalized) else { continue }
            let raw = decodeHTML(String(normalized[swiftRange]))
            if !urls.contains(raw) { urls.append(raw) }
        }
        return urls
    }

    private static func isTwitterImageCDN(_ url: String) -> Bool {
        let lower = url.lowercased()
        guard lower.contains("pbs.twimg.com/") else { return false }
        return lower.contains("/media/")
            || lower.contains("/card_img/")
            || lower.contains("/amplify_video_thumb/")
            || lower.contains("/ext_tw_video_thumb/")
            || lower.contains("/tweet_video_thumb/")
    }

    private static func preferredTwitterMediaURL(_ url: String) -> String {
        // Ask for a larger JPEG — webp thumbs are tiny and some iOS builds are picky.
        guard let parsed = URL(string: url),
              var comps = URLComponents(url: parsed, resolvingAgainstBaseURL: false) else {
            return url
        }
        let path = comps.path
        if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") || path.hasSuffix(".png") || path.hasSuffix(".webp") {
            comps.path = (path as NSString).deletingPathExtension
        }
        var items = comps.queryItems ?? []
        items.removeAll { $0.name == "format" || $0.name == "name" }
        items.append(URLQueryItem(name: "format", value: "jpg"))
        items.append(URLQueryItem(name: "name", value: "large"))
        comps.queryItems = items
        return comps.url?.absoluteString ?? url
    }

    private static func fetchTikTokOEmbed(_ url: URL) async -> Result {
        var result = await requestTikTokOEmbed(url)
        if result.image == nil, let resolved = await finalURL(afterRedirects: url),
           resolved.absoluteString != url.absoluteString {
            let retry = await requestTikTokOEmbed(resolved)
            if result.title == nil { result.title = retry.title }
            if result.image == nil { result.image = retry.image }
        }
        return result
    }

    private static func requestTikTokOEmbed(_ url: URL) async -> Result {
        guard let oembedURL = oembedURL(for: url) else { return Result() }
        do {
            var request = URLRequest(url: oembedURL, timeoutInterval: 12)
            request.setValue(safariUA, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return Result()
            }
            let title = (json["title"] as? String).map(clean)
            var image: UIImage?
            if let thumb = json["thumbnail_url"] as? String, !thumb.isEmpty {
                image = await downloadImageURL(thumb, referer: URL(string: "https://www.tiktok.com/"))
            }
            return Result(title: title, description: nil, image: image)
        } catch {
            return Result()
        }
    }

    private static func finalURL(afterRedirects url: URL) async -> URL? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(safariUA, forHTTPHeaderField: "User-Agent")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response.url
        } catch {
            return nil
        }
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
