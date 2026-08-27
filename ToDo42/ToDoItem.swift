import Foundation
import SwiftData

enum ItemCategory: String, CaseIterable, Identifiable {
    case places, fun, eats
    var id: String { rawValue }
    var title: String {
        switch self {
        case .places: "Places"
        case .fun: "Fun"
        case .eats: "Eats"
        }
    }
    var systemImage: String {
        switch self {
        case .places: "mappin.and.ellipse"
        case .fun: "sailboat.fill"
        case .eats: "fork.knife"
        }
    }
}

@Model
final class TodoItem {
    var id: UUID
    var title: String
    var urlString: String?
    var imageAssetName: String?
    var imageURLString: String?
    var imageData: Data?
    var notes: String = ""
    var chrisHearted: Bool = false
    var deenaHearted: Bool = false
    var categoryRaw: String
    var isDone: Bool
    var createdAt: Date

    init(
        title: String,
        category: ItemCategory,
        urlString: String? = nil,
        imageAssetName: String? = nil,
        imageURLString: String? = nil,
        imageData: Data? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.categoryRaw = category.rawValue
        self.urlString = urlString
        self.imageAssetName = imageAssetName
        self.imageURLString = imageURLString
        self.imageData = imageData
        self.notes = notes
        self.chrisHearted = false
        self.deenaHearted = false
        self.isDone = false
        self.createdAt = .now
    }

    var category: ItemCategory {
        get { ItemCategory(rawValue: categoryRaw) ?? .places }
        set { categoryRaw = newValue.rawValue }
    }

    var hasPhoto: Bool {
        if let data = imageData, !data.isEmpty { return true }
        if let name = imageAssetName, !name.isEmpty { return true }
        if let url = imageURLString, !url.isEmpty { return true }
        return false
    }

    var usesCompactSharedText: Bool {
        SharedCopy.isInstagramOrAirbnb(urlString: urlString ?? "", title: title)
    }

    var displayTitle: String {
        usesCompactSharedText ? SharedCopy.clamped(title) : title
    }

    var displayNotes: String {
        usesCompactSharedText ? SharedCopy.clamped(notes) : notes
    }
}

enum SampleData {
    struct Seed {
        let title: String
        let category: ItemCategory
        let urlString: String
        let imageAssetName: String
        let notes: String
    }

    static let seeds: [Seed] = [
        Seed(title: "Lake House", category: .places, urlString: "https://maps.apple.com/?q=Lake+House", imageAssetName: "LakeHouse", notes: "Weekend getaway"),
        Seed(title: "Beach", category: .places, urlString: "https://maps.apple.com/?q=Beach", imageAssetName: "Beach", notes: "Sunset picnic"),
        Seed(title: "Mountain Cabin", category: .places, urlString: "https://maps.apple.com/?q=Mountain+Cabin", imageAssetName: "MountainCabin", notes: "Fall weekend"),
        Seed(title: "Hobie Sailing", category: .fun, urlString: "https://www.hobie.com/", imageAssetName: "HobieSailing", notes: "Book a lesson"),
        Seed(title: "Lemon Garlic Pasta", category: .eats, urlString: "https://www.allrecipes.com/", imageAssetName: "LemonGarlicPasta", notes: "30-min recipe"),
    ]

    static func matching(title: String) -> Seed? {
        seeds.first { $0.title == title }
    }

    static func makeItem(_ seed: Seed) -> TodoItem {
        TodoItem(
            title: seed.title,
            category: seed.category,
            urlString: seed.urlString,
            imageAssetName: seed.imageAssetName,
            notes: seed.notes
        )
    }
}
