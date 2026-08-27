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

enum SharedCopy {
    static let characterLimit = 300

    static func isInstagramOrAirbnb(urlString: String, title: String = "") -> Bool {
        let hay = "\(urlString) \(title)".lowercased()
        return hay.contains("instagram") || hay.contains("airbnb")
    }

    static func clamped(_ text: String, limit: Int = characterLimit) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        var clipped = String(trimmed[..<end])
        if let space = clipped.lastIndex(where: { $0.isWhitespace }),
           clipped.distance(from: clipped.startIndex, to: space) >= limit / 2 {
            clipped = String(clipped[..<space])
        }
        return clipped.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

enum ShareInbox {
    static func save(payload: SharePayload, image: UIImage?) throws {
        guard let inbox = AppGroup.inboxURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        var payload = payload
        let id = UUID().uuidString

        if let image, let data = jpegData(from: image) {
            let fileName = "\(id).jpg"
            try data.write(to: inbox.appendingPathComponent(fileName), options: .atomic)
            payload.imageFileName = fileName
        }

        let data = try JSONEncoder().encode(payload)
        try data.write(to: inbox.appendingPathComponent("\(id).json"), options: .atomic)
    }

    static func jpegData(from image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        let scaled: UIImage
        if longest > maxSide {
            let scale = maxSide / longest
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        } else {
            scaled = image
        }
        return scaled.jpegData(compressionQuality: 0.82)
    }

    static func guessedCategory(urlString: String, title: String) -> String {
        let haystack = "\(urlString) \(title)".lowercased()
        if haystack.contains("airbnb") || haystack.contains("vrbo") || haystack.contains("hotel") || haystack.contains("maps.apple") {
            return "places"
        }
        if haystack.contains("allrecipes") || haystack.contains("nytimes.com/cooking") || haystack.contains("yelp") || haystack.contains("opentable") {
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
