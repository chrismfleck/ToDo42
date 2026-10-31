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

struct IdeaPromptCategory: Equatable {
    var name: String
    var kind: String
}

enum IdeaPrompt {
    static let existingLimit = 12

    static func guidance(for kind: String, hasSaved: Bool) -> String {
        switch kind {
        case "places":
            hasSaved
                ? "places to stay for two that are similar to the places already saved on this list"
                : "places to stay for two, such as a cabin, inn, hotel, or vacation rental"
        case "fun":
            hasSaved
                ? "fun things for two people to do nearby that are similar to the activities already saved on this list"
                : "fun activities for two people to do together, within about an hour of home"
        case "eats":
            "restaurants and places to eat out for two, within about an hour of home"
        case "projects":
            "home projects the two of us can do together at home"
        case "recipe":
            "recipes for two people to cook together at home. Each link must open a recipe page, not a restaurant, a store, or a trip"
        case "health":
            "health tips for two people. Each link must open a practical health article or guide"
        case "vegas":
            "things for two people to do in Las Vegas. Keep every idea in Las Vegas, not near home"
        case "london":
            "things for two people to do in London. Keep every idea in London, not near home"
        case "dc":
            "things for two people to do in Washington, DC. Keep every idea in Washington, DC, not near home"
        default:
            "ideas that fit this list"
        }
    }

    static func text(
        homeLabel: String?,
        categories: [IdeaPromptCategory],
        existing: [IdeaListLine],
        keywords: String
    ) -> String {
        let chosen = categories.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let home = homeLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let homeLine = home.isEmpty
            ? "We have not set a home location."
            : "We live near \(home)."

        let hasSaved = existing.contains {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var lines = ["\(homeLine) We are a couple.", ""]
        if chosen.isEmpty {
            lines.append("Suggest ideas for this list. These must be \(guidance(for: "", hasSaved: false)).")
        } else if chosen.count == 1, let only = chosen.first {
            let name = only.name.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("Suggest ideas for \(name). These must be \(guidance(for: only.kind, hasSaved: hasSaved)).")
        } else {
            lines.append("Suggest ideas for each category below. Keep each idea in its own category.")
            for category in chosen {
                let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append("- \(name): \(guidance(for: category.kind, hasSaved: hasSaved)).")
            }
        }

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
            let kinds = Set(chosen.map(\.kind))
            if kinds.contains("places"), kinds.contains("fun") {
                lines.append("Suggest a new place to stay similar to the saved places, and something fun nearby similar to the saved activities.")
            } else if kinds.contains("places") {
                lines.append("Suggest a new place to stay similar to the saved places.")
            } else if kinds.contains("fun") {
                lines.append("Suggest something fun nearby similar to the saved activities.")
            }
        }

        let words = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty {
            lines.append("")
            lines.append("Also use these keywords: \(words).")
        }

        lines.append("")
        lines.append("Suggest 8 new ideas.")
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
    categories: [IdeaPromptCategory(name: "Fun 4 Two", kind: "fun")],
    existing: [IdeaListLine(title: "Hobie Sailing", notes: "Book a lesson", url: "https://www.hobie.com/")],
    keywords: "sunset"
)
expect(prompt.contains("We live near Annapolis, MD."), "prompt home")
expect(prompt.contains("Suggest ideas for Fun 4 Two. These must be fun things for two people to do nearby that are similar to the activities already saved on this list."), "prompt fun")
expect(prompt.contains("Suggest something fun nearby similar to the saved activities."), "prompt fun follow-up")

let stays = IdeaPrompt.text(
    homeLabel: "Annapolis, MD",
    categories: [IdeaPromptCategory(name: "Bed 4 Two", kind: "places")],
    existing: [IdeaListLine(title: "Lake House", notes: "Weekend getaway", url: "https://maps.apple.com/?q=Lake+House")],
    keywords: ""
)
expect(stays.contains("places to stay for two that are similar to the places already saved on this list"), "places match the list")
expect(stays.contains("Suggest a new place to stay similar to the saved places."), "places follow-up")
expect(prompt.contains("Hobie Sailing — Book a lesson — https://www.hobie.com/"), "prompt existing")
expect(prompt.contains("Also use these keywords: sunset."), "prompt keywords")

let recipe = IdeaPrompt.text(
    homeLabel: "Annapolis, MD",
    categories: [IdeaPromptCategory(name: "Recipe 4 Two", kind: "recipe")],
    existing: [],
    keywords: ""
)
expect(recipe.contains("recipes for two people to cook together at home"), "recipe asks for recipes")
expect(recipe.contains("recipe page"), "recipe asks for a recipe link")
expect(!recipe.contains("hour of home"), "recipe is not a nearby outing")
expect(!recipe.contains("Las Vegas"), "recipe is not a trip")

let expected: [(String, String)] = [
    ("places", "places to stay for two"),
    ("fun", "fun activities for two people"),
    ("eats", "restaurants and places to eat out"),
    ("projects", "home projects"),
    ("recipe", "recipes for two people to cook"),
    ("health", "health tips for two people"),
    ("vegas", "in Las Vegas"),
    ("london", "in London"),
    ("dc", "in Washington, DC"),
]
for pair in expected {
    let sample = IdeaPrompt.text(
        homeLabel: nil,
        categories: [IdeaPromptCategory(name: pair.0, kind: pair.0)],
        existing: [],
        keywords: ""
    )
    expect(sample.contains(pair.1), "prompt kind \(pair.0)")
}

let noHome = IdeaPrompt.text(homeLabel: "  ", categories: [], existing: [], keywords: "")
expect(noHome.contains("We have not set a home location."), "missing home")
expect(noHome.contains("ideas that fit this list"), "missing category fallback")

if failed > 0 {
    fputs("\(failed) failed\n", stderr)
    exit(1)
}
print("ok")
