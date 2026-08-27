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
    static func consumeDrafts() -> [(SharePayload, Data?)] {
        guard let inbox = AppGroup.inboxURL else { return [] }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return [] }

        var drafts: [(SharePayload, Data?)] = []
        for jsonURL in files.filter({ $0.pathExtension == "json" }) {
            guard let data = try? Data(contentsOf: jsonURL),
                  let payload = try? JSONDecoder().decode(SharePayload.self, from: data) else { continue }
            var imageData: Data?
            if let name = payload.imageFileName {
                let imageURL = inbox.appendingPathComponent(name)
                imageData = try? Data(contentsOf: imageURL)
                try? fm.removeItem(at: imageURL)
            }
            try? fm.removeItem(at: jsonURL)
            drafts.append((payload, imageData))
        }
        return drafts
    }
}
