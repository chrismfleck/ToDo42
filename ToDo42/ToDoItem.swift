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
        Seed(
            title: "Lake Escape 2",
            category: .places,
            urlString: "https://www.airbnb.com/rooms/810901494684354420?photo_id=1572097457&source_impression_id=p3_1788720795_P3m5HyIdx_dI3pKD",
            imageAssetName: "LakeEscape",
            notes: "Dock, kayaks, fire pit"
        ),
        Seed(
            title: "Greek Seas Charter Sailing",
            category: .fun,
            urlString: "https://share.google/jvIvhY1em9UXeMeEh",
            imageAssetName: "GreekSailing",
            notes: "Athens sailing"
        ),
        Seed(
            title: "Keto recipe",
            category: .eats,
            urlString: "https://www.instagram.com/reel/Cw0BCo0vBC9/?utm_source=ig_web_copy_link&stkn=MzRlODBiNWFlZA==",
            imageAssetName: "KetoRecipe",
            notes: "Reel recipe"
        ),
    ]

    static let previousTitles = [
        "Lake House", "Beach", "Mountain Cabin", "Hobie Sailing", "Lemon Garlic Pasta",
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
