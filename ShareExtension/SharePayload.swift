import Foundation
import UIKit

enum AppGroup {
    static let id = "group.com.chrisfleck.ToDo42"

    static var inboxURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: id)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }
}

struct SharePayload: Codable {
    var title: String
    var urlString: String
    var notes: String
    var category: String
    var imageFileName: String?
}

enum ShareInbox {
    static func save(payload: SharePayload, image: UIImage?) throws {
        guard let inbox = AppGroup.inboxURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        var payload = payload
        let id = UUID().uuidString

        if let image, let data = ShareMedia.jpegData(from: image) {
            let fileName = "\(id).jpg"
            try data.write(to: inbox.appendingPathComponent(fileName), options: .atomic)
            payload.imageFileName = fileName
        }

        let data = try JSONEncoder().encode(payload)
        try data.write(to: inbox.appendingPathComponent("\(id).json"), options: .atomic)
    }

    static let categoryDefaults: [(raw: String, title: String)] = [
        ("places", "Bed 4 Two"),
        ("fun", "Fun 4 Two"),
        ("eats", "Table 4 Two"),
        ("trip", "Trip 4 Two"),
        ("recipe", "Recipe 4 Two"),
        ("health", "Health Tips 4 Two"),
    ]

    static func categoryTitle(_ raw: String) -> String {
        let stored = UserDefaults(suiteName: AppGroup.id)?
            .dictionary(forKey: "todo42.categoryTitles") as? [String: String]
        let custom = stored?[raw]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        return categoryDefaults.first { $0.raw == raw }?.title ?? raw
    }

    static func categorySymbol(_ raw: String) -> String {
        switch raw {
        case "places": return "bed.double.fill"
        case "fun": return "sailboat.fill"
        case "eats": return "fork.knife"
        case "trip": return "airplane"
        case "recipe": return "frying.pan.fill"
        case "health": return "heart.text.square.fill"
        default: return "square.grid.2x2"
        }
    }

    static func guessedCategory(urlString: String, title: String) -> String {
        let haystack = "\(urlString) \(title)".lowercased()
        if haystack.contains("airbnb") || haystack.contains("vrbo") || haystack.contains("hotel") || haystack.contains("maps.apple") {
            return "places"
        }
        if haystack.contains("allrecipes")
            || haystack.contains("nytimes.com/cooking")
            || haystack.contains("recipe")
            || haystack.contains("ingredients") {
            return "recipe"
        }
        if haystack.contains("yelp")
            || haystack.contains("opentable")
            || haystack.contains("restaurant") {
            return "eats"
        }
        if haystack.contains("webmd")
            || haystack.contains("healthline")
            || haystack.contains("health tip")
            || haystack.contains("wellness") {
            return "health"
        }
        if haystack.contains("tripadvisor")
            || haystack.contains("expedia")
            || haystack.contains("kayak.com")
            || haystack.contains("google.com/travel") {
            return "trip"
        }
        if haystack.contains("instagram")
            || haystack.contains("youtube")
            || haystack.contains("tiktok")
            || haystack.contains("x.com")
            || haystack.contains("twitter.com")
            || haystack.contains("t.co")
            || haystack.contains("facebook.com")
            || haystack.contains("fb.com")
            || haystack.contains("fb.watch") {
            return "fun"
        }
        return "places"
    }
}
