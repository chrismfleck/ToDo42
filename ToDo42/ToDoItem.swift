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
    var extraImageData: Data?
    var notes: String = ""
    var chrisHearted: Bool = false
    var deenaHearted: Bool = false
    var categoryRaw: String
    var isDone: Bool
    var createdAt: Date
    var sortOrder: Int = 0
    var updatedAt: Date?
    var lastEditor: String = ""

    init(
        title: String,
        category: ItemCategory,
        urlString: String? = nil,
        imageAssetName: String? = nil,
        imageURLString: String? = nil,
        imageData: Data? = nil,
        extraImageData: Data? = nil,
        notes: String = "",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.categoryRaw = category.rawValue
        self.urlString = urlString
        self.imageAssetName = imageAssetName
        self.imageURLString = imageURLString
        self.imageData = imageData
        self.extraImageData = extraImageData
        self.notes = notes
        self.chrisHearted = false
        self.deenaHearted = false
        self.isDone = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortOrder = sortOrder
        self.lastEditor = ""
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

    var hasExtraPhoto: Bool {
        if let data = extraImageData, !data.isEmpty { return true }
        return false
    }
}

enum ItemStore {
    static func allItems(in context: ModelContext) -> [TodoItem] {
        (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
    }

    static func item(id: UUID, in context: ModelContext) -> TodoItem? {
        allItems(in: context).first { $0.id == id }
    }

    static func keyedByID(_ items: [TodoItem]) -> [String: TodoItem] {
        Dictionary(items.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Build 42 stored bottom photos as TDItem rows with a blank title and the
    /// extra image in `image`. If those rows were applied as list items, keep
    /// that photo as the extra before a later pull restores the real primary.
    static func preserveMisplacedExtraPhotos(in items: [TodoItem]) {
        for item in items {
            let emptyTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard emptyTitle else { continue }
            if item.extraImageData == nil, let data = item.imageData, !data.isEmpty {
                item.extraImageData = data
            }
        }
    }

    static func deduplicate(in context: ModelContext) {
        let items = allItems(in: context)
        preserveMisplacedExtraPhotos(in: items)
        var keepers: [UUID: TodoItem] = [:]
        var extras: [TodoItem] = []
        for item in items {
            guard let current = keepers[item.id] else {
                keepers[item.id] = item
                continue
            }
            let keepCurrent = ItemDuplicatePick.keepFirst(
                firstUpdated: current.updatedAt ?? current.createdAt,
                firstHasPhoto: current.hasPhoto,
                firstNoteCount: current.notes.count,
                firstTitleEmpty: current.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                secondUpdated: item.updatedAt ?? item.createdAt,
                secondHasPhoto: item.hasPhoto,
                secondNoteCount: item.notes.count,
                secondTitleEmpty: item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            if keepCurrent {
                extras.append(item)
            } else {
                extras.append(current)
                keepers[item.id] = item
            }
        }
        guard !extras.isEmpty else { return }
        for extra in extras {
            guard let keep = keepers[extra.id] else { continue }
            keep.chrisHearted = keep.chrisHearted || extra.chrisHearted
            keep.deenaHearted = keep.deenaHearted || extra.deenaHearted
            if keep.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               extra.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                keep.title = extra.title
            }
            if keep.notes.isEmpty, extra.notes.isEmpty == false {
                keep.notes = extra.notes
            }
            if keep.imageData == nil, let data = extra.imageData, data.isEmpty == false {
                keep.imageData = data
            }
            if keep.extraImageData == nil, let data = extra.extraImageData, data.isEmpty == false {
                keep.extraImageData = data
            }
            context.delete(extra)
        }
        try? context.save()
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

    static func makeItem(_ seed: Seed, sortOrder: Int = 0) -> TodoItem {
        TodoItem(
            title: seed.title,
            category: seed.category,
            urlString: seed.urlString,
            imageAssetName: seed.imageAssetName,
            notes: seed.notes,
            sortOrder: sortOrder
        )
    }
}
