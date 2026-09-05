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

    static func guessedCategory(urlString: String, title: String) -> String {
        let haystack = "\(urlString) \(title)".lowercased()
        if haystack.contains("airbnb") || haystack.contains("vrbo") || haystack.contains("hotel") || haystack.contains("maps.apple") {
            return "places"
        }
        if haystack.contains("allrecipes")
            || haystack.contains("nytimes.com/cooking")
            || haystack.contains("yelp")
            || haystack.contains("opentable")
            || haystack.contains("recipe")
            || haystack.contains("ingredients") {
            return "eats"
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
