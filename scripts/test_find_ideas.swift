import Foundation

enum IdeaSource: String, CaseIterable {
    case airbnb, google, maps, instagram, tiktok, x, tripadvisor

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
                string = "https://www.instagram.com/explore/search/keyword/?q=\(encodedTags)"
            }
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
expect(instagram.contains("instagram.com"), "instagram host")
expect(instagram.contains("%23asheville"), "instagram hash asheville")
expect(instagram.contains("%23cabin"), "instagram hash cabin")
expect(instagram.contains("%23hot"), "instagram hash hot")
expect(instagram.contains("%23tub"), "instagram hash tub")
expect(IdeaSource.instagram.opensInAppBrowser, "instagram in-app")
expect(IdeaSource.instagram.nativeSearchURLs(keywords: query).isEmpty, "instagram has no native scheme")
expect(IdeaSource.hashtagQuery(query) == "#asheville #cabin #hot #tub", "hashtag query")

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

if failed > 0 {
    fputs("\(failed) failed\n", stderr)
    exit(1)
}
print("ok")
