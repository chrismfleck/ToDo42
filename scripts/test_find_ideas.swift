import Foundation

enum IdeaSource: String, CaseIterable {
    case airbnb, google, maps, instagram, tiktok, tripadvisor

    var opensInAppBrowser: Bool {
        switch self {
        case .instagram, .tiktok: false
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
            string = query.isEmpty
                ? "https://www.instagram.com/"
                : "https://www.instagram.com/explore/search/keyword/?q=\(encoded)"
        case .tiktok:
            string = query.isEmpty
                ? "https://www.tiktok.com/"
                : "https://www.tiktok.com/search?q=\(encoded)"
        case .tripadvisor:
            string = query.isEmpty
                ? "https://www.tripadvisor.com/"
                : "https://www.tripadvisor.com/Search?q=\(encoded)"
        }
        return URL(string: string)
    }

    var nativeAppURLs: [URL] {
        switch self {
        case .instagram:
            [URL(string: "instagram://app")].compactMap { $0 }
        case .tiktok:
            [URL(string: "tiktok://"), URL(string: "snssdk1233://")].compactMap { $0 }
        default:
            []
        }
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
expect(!IdeaSource.instagram.opensInAppBrowser, "instagram opens app")

let tiktok = IdeaSource.tiktok.searchURL(keywords: query)?.absoluteString ?? ""
expect(tiktok.contains("tiktok.com/search"), "tiktok search")
expect(!IdeaSource.tiktok.opensInAppBrowser, "tiktok opens app")

let tripadvisor = IdeaSource.tripadvisor.searchURL(keywords: query)?.absoluteString ?? ""
expect(tripadvisor.contains("tripadvisor.com/Search"), "tripadvisor search")
expect(IdeaSource.airbnb.opensInAppBrowser, "airbnb in-app")
expect(IdeaSource.google.opensInAppBrowser, "google in-app")
expect(IdeaSource.maps.opensInAppBrowser, "maps in-app")
expect(IdeaSource.tripadvisor.opensInAppBrowser, "tripadvisor in-app")
expect(!IdeaSource.instagram.nativeAppURLs.isEmpty, "instagram app url")
expect(!IdeaSource.tiktok.nativeAppURLs.isEmpty, "tiktok app url")
expect(IdeaSource.airbnb.nativeAppURLs.isEmpty, "airbnb has no native scheme")

let emptyAirbnb = IdeaSource.airbnb.searchURL(keywords: "  ")?.absoluteString ?? ""
expect(emptyAirbnb == "https://www.airbnb.com/", "empty airbnb homepage")

if failed > 0 {
    fputs("\(failed) failed\n", stderr)
    exit(1)
}
print("ok")
