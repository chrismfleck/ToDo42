import Foundation

enum IdeaSource: String, CaseIterable {
    case airbnb, google, maps, instagram, pinterest, tiktok, x, tripadvisor

    var opensInAppBrowser: Bool {
        switch self {
        case .tiktok: false
        default: true
        }
    }

    func searchURL(keywords: String) -> URL? {
        let query = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let string: String
        switch self {
        case .airbnb:
            string = query.isEmpty
                ? "https://www.airbnb.com/"
                : "https://www.airbnb.com/s/homes?query=\(encoded)"
        case .google:
            string = query.isEmpty
                ? "https://www.google.com/"
                : "https://www.google.com/search?q=\(encoded)"
        case .maps:
            string = query.isEmpty
                ? "https://maps.apple.com/"
                : "https://maps.apple.com/?q=\(encoded)"
        case .instagram:
            if query.isEmpty {
                string = "https://www.instagram.com/"
            } else {
                let tags = Self.hashtagQuery(query)
                let encodedTags = tags.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                string = "https://www.google.com/search?q=\(encodedTags)+site:instagram.com"
            }
        case .pinterest:
            string = query.isEmpty
                ? "https://www.pinterest.com/"
                : "https://www.pinterest.com/search/pins/?q=\(encoded)"
        case .tiktok:
            string = query.isEmpty
                ? "https://www.tiktok.com/"
                : "https://www.tiktok.com/search?q=\(encoded)"
        case .x:
            string = query.isEmpty
                ? "https://x.com/"
                : "https://x.com/search?q=\(encoded)"
        case .tripadvisor:
            string = query.isEmpty
                ? "https://www.tripadvisor.com/"
                : "https://www.tripadvisor.com/Search?q=\(encoded)"
        }
        return URL(string: string)
    }

    func nativeSearchURLs(keywords: String) -> [URL] {
        let query = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let tags = Self.hashtagSlugs(query)
        switch self {
        case .instagram:
            return []
        case .tiktok:
            if query.isEmpty {
                return [URL(string: "tiktok://"), URL(string: "snssdk1233://")].compactMap { $0 }
            }
            var urls = [
                URL(string: "snssdk1233://search?keyword=\(encoded)"),
                URL(string: "tiktok://search?keyword=\(encoded)"),
                URL(string: "aweme://search?keyword=\(encoded)"),
            ]
            urls += tags.map { URL(string: "tiktok://hashtag/\($0)") }
            return urls.compactMap { $0 }
        default:
            return []
        }
    }

    static func hashtagWords(_ keywords: String) -> [String] {
        keywords
            .folding(options: .diacriticInsensitive, locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func hashtagQuery(_ keywords: String) -> String {
        hashtagWords(keywords).map { "#\($0)" }.joined(separator: " ")
    }

    static func hashtagSlugs(_ keywords: String) -> [String] {
        let words = hashtagWords(keywords)
        var slugs = words
        let joined = words.joined()
        if !joined.isEmpty, !slugs.contains(joined) {
            slugs.append(joined)
        }
        return slugs
    }
}

enum IdeaAssistant: String {
    case grok
    case chatgpt

    func askURL(prompt: String) -> URL? {
        let host = self == .grok ? "https://grok.com/" : "https://chatgpt.com/"
        var components = URLComponents(string: host)
        components?.queryItems = [URLQueryItem(name: "q", value: prompt)]
        return components?.url
    }
}

struct IdeaListLine: Equatable {
    var title: String
    var notes: String
    var url: String?
}

enum IdeaPrompt {
    static let existingLimit = 12

    static func text(
        homeLabel: String?,
        categoryNames: [String],
        existing: [IdeaListLine],
        keywords: String
    ) -> String {
        let names = categoryNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let categoryPhrase = names.isEmpty ? "this list" : names.joined(separator: " and ")
        let home = homeLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let homeLine = home.isEmpty
            ? "We have not set a home location."
            : "We live near \(home)."

        var lines = [
            "\(homeLine) We are a couple looking for ideas for \(categoryPhrase).",
            "",
            "The ideas must fit this category: \(categoryPhrase)."
        ]

        let saved = existing.prefix(existingLimit)
        if !saved.isEmpty {
            lines.append("")
            lines.append("Already saved. Do not suggest these again:")
            for item in saved {
                var bullet = "- \(item.title)"
                let notes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !notes.isEmpty {
                    bullet += " — \(notes)"
                }
                if let url = item.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                    bullet += " — \(url)"
                }
                lines.append(bullet)
            }
        }

        let words = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty {
            lines.append("")
            lines.append("Also use these keywords: \(words).")
        }

        lines.append("")
        lines.append("Suggest 8 new ideas for \(categoryPhrase), within about an hour of home when that fits. For a trip category, suggest ideas in that destination.")
        lines.append("")
        lines.append("Reply with only a list. One item per line:")
        lines.append("Title — one sentence why it fits — https://full-link")
        lines.append("")
        lines.append("Each link must be a real page we can open.")
        return lines.joined(separator: "\n")
    }
}

var failed = 0
func expect(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL \(message)\n", stderr)
        failed += 1
    }
}

let query = "Asheville cabin hot tub"
let airbnb = IdeaSource.airbnb.searchURL(keywords: query)?.absoluteString ?? ""
expect(airbnb.contains("airbnb.com/s/homes"), "airbnb search path")
expect(airbnb.contains("query=Asheville"), "airbnb query")

let google = IdeaSource.google.searchURL(keywords: query)?.absoluteString ?? ""
expect(google.contains("google.com/search?q="), "google search")

let maps = IdeaSource.maps.searchURL(keywords: query)?.absoluteString ?? ""
expect(maps.contains("maps.apple.com"), "maps host")
expect(maps.contains("q=Asheville"), "maps query")

let instagram = IdeaSource.instagram.searchURL(keywords: query)?.absoluteString ?? ""
expect(instagram.contains("google.com/search"), "instagram search keeps all tags")
expect(instagram.contains("%23asheville"), "instagram hash asheville")
expect(instagram.contains("%23cabin"), "instagram hash cabin")
expect(instagram.contains("%23hot"), "instagram hash hot")
expect(instagram.contains("%23tub"), "instagram hash tub")
expect(instagram.contains("site:instagram.com") || instagram.contains("site%3Ainstagram.com"), "instagram scoped")
expect(IdeaSource.instagram.opensInAppBrowser, "instagram in-app")
expect(IdeaSource.instagram.nativeSearchURLs(keywords: query).isEmpty, "instagram has no native scheme")
expect(IdeaSource.hashtagQuery(query) == "#asheville #cabin #hot #tub", "hashtag query")

let pinterest = IdeaSource.pinterest.searchURL(keywords: query)?.absoluteString ?? ""
expect(pinterest.contains("pinterest.com/search/pins/"), "pinterest search")
expect(pinterest.contains("q=Asheville"), "pinterest query")
expect(IdeaSource.pinterest.opensInAppBrowser, "pinterest in-app")
expect(IdeaSource.pinterest.nativeSearchURLs(keywords: query).isEmpty, "pinterest has no native scheme")
let emptyPinterest = IdeaSource.pinterest.searchURL(keywords: "  ")?.absoluteString ?? ""
expect(emptyPinterest == "https://www.pinterest.com/", "empty pinterest homepage")

let tiktok = IdeaSource.tiktok.searchURL(keywords: query)?.absoluteString ?? ""
expect(tiktok.contains("tiktok.com/search"), "tiktok search")
expect(tiktok.contains("q=Asheville"), "tiktok query")
expect(!IdeaSource.tiktok.opensInAppBrowser, "tiktok opens app")
let ttNative = IdeaSource.tiktok.nativeSearchURLs(keywords: query).map(\.absoluteString)
expect(ttNative.contains { $0.contains("search?keyword=") }, "tiktok native search")
expect(ttNative.contains { $0.contains("Asheville") }, "tiktok native keeps keywords")

let x = IdeaSource.x.searchURL(keywords: query)?.absoluteString ?? ""
expect(x.contains("x.com/search"), "x search")
expect(x.contains("q=Asheville"), "x query")
expect(IdeaSource.x.opensInAppBrowser, "x in-app")
expect(IdeaSource.x.nativeSearchURLs(keywords: query).isEmpty, "x has no native scheme")

let tripadvisor = IdeaSource.tripadvisor.searchURL(keywords: query)?.absoluteString ?? ""
expect(tripadvisor.contains("tripadvisor.com/Search"), "tripadvisor search")
expect(IdeaSource.airbnb.opensInAppBrowser, "airbnb in-app")
expect(IdeaSource.google.opensInAppBrowser, "google in-app")
expect(IdeaSource.maps.opensInAppBrowser, "maps in-app")
expect(IdeaSource.tripadvisor.opensInAppBrowser, "tripadvisor in-app")
expect(IdeaSource.instagram.nativeSearchURLs(keywords: query).isEmpty, "instagram stays in-app")
expect(!IdeaSource.tiktok.nativeSearchURLs(keywords: query).isEmpty, "tiktok app url")
expect(IdeaSource.airbnb.nativeSearchURLs(keywords: query).isEmpty, "airbnb has no native scheme")
expect(IdeaSource.hashtagSlugs(query) == ["asheville", "cabin", "hot", "tub", "ashevillecabinhottub"], "hashtag slugs")

let emptyAirbnb = IdeaSource.airbnb.searchURL(keywords: "  ")?.absoluteString ?? ""
expect(emptyAirbnb == "https://www.airbnb.com/", "empty airbnb homepage")

let grok = IdeaAssistant.grok.askURL(prompt: "Fun 4 Two cabin")?.absoluteString ?? ""
expect(grok.hasPrefix("https://grok.com/?q="), "grok host")
expect(grok.contains("Fun"), "grok keeps category words")
expect(grok.contains("cabin"), "grok keeps the rest of the prompt")

let chat = IdeaAssistant.chatgpt.askURL(prompt: "Table 4 Two")?.absoluteString ?? ""
expect(chat.hasPrefix("https://chatgpt.com/?q="), "chatgpt host")
expect(chat.contains("Table"), "chatgpt keeps category words")

let prompt = IdeaPrompt.text(
    homeLabel: "Annapolis, MD",
    categoryNames: ["Fun 4 Two"],
    existing: [IdeaListLine(title: "Hobie Sailing", notes: "Book a lesson", url: "https://www.hobie.com/")],
    keywords: "sunset"
)
expect(prompt.contains("We live near Annapolis, MD."), "prompt home")
expect(prompt.contains("The ideas must fit this category: Fun 4 Two."), "prompt category")
expect(prompt.contains("Hobie Sailing — Book a lesson — https://www.hobie.com/"), "prompt existing")
expect(prompt.contains("Also use these keywords: sunset."), "prompt keywords")

let noHome = IdeaPrompt.text(homeLabel: "  ", categoryNames: [], existing: [], keywords: "")
expect(noHome.contains("We have not set a home location."), "missing home")
expect(noHome.contains("The ideas must fit this category: this list."), "missing category fallback")

if failed > 0 {
    fputs("\(failed) failed\n", stderr)
    exit(1)
}
print("ok")
