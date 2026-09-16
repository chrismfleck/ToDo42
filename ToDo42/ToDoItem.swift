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

    static func guessed(urlString: String, title: String) -> ItemCategory {
        let haystack = "\(urlString) \(title)".lowercased()
        if haystack.contains("airbnb") || haystack.contains("vrbo") || haystack.contains("hotel") || haystack.contains("maps.apple") {
            return .places
        }
        if haystack.contains("allrecipes")
            || haystack.contains("nytimes.com/cooking")
            || haystack.contains("yelp")
            || haystack.contains("opentable")
            || haystack.contains("recipe")
            || haystack.contains("ingredients") {
            return .eats
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
            return .fun
        }
        return .places
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
        Seed(
            title: "Luxury private lakefront Barn Loft + Silo Jacuzzi",
            category: .places,
            urlString: "https://www.airbnb.com/rooms/1660244481236892848?guests=1&adults=1&s=67&unique_share_id=5661229e-e8c6-4e11-8e7f-277755cb63ad&source_impression_id=p3_1789326720_P3s9gNohwU3CVQDm",
            imageAssetName: "BarnLoft",
            notes: "Escape to a one-of-a-kind private lakefront barn loft on peaceful farmland in Dade City. Designed with dreamy Victorian style, antique character, and a romantic high-end boutique feel, this stay blends rustic charm with elevated comfort. Unwind in the silo jacuzzi, enjoy slow mornings on the deck beneath the trees, watch movies on the large-screen projector, and meet our friendly farm animals for a magical agritourism escape that feels private, special, and luxurious."
        ),
        Seed(
            title: "Eco-Luxurious Lakefront haven (Fire pit & Hot Tub)",
            category: .places,
            urlString: "https://www.airbnb.com/rooms/976091434015163591?guests=1&adults=1&s=67&unique_share_id=a44a02db-6b0b-4827-9cf5-b54bd6422955&source_impression_id=p3_1789326918_P3ns_i-_2TQK7qY2",
            imageAssetName: "EcoLuxHaven",
            notes: """
            Experience the perfect blend of an eco-friendly retreat and modern luxury of our lakefront container home. Nestled in the heart of nature, this stylish oasis promises an unforgettable experience where you can immerse yourself amidst the beauty of the countryside without sacrificing comfort. Plus, enjoy the opportunity to interact with our farm animals, adding a touch of rural charm to your agritourism escape.

            Also, feel free to check out  my other listing, Casa de Elvira on my host profile.
            """
        ),
        Seed(
            title: "Sail Greece as a Traveler, Not a Tourist",
            category: .places,
            urlString: "https://greekseas.com/",
            imageAssetName: "GreekSeas",
            notes: "The Lagoon 450 is where comfort meets performance. This spacious luxury catamaran is designed for groups who want to experience the Greek islands without compromising on space or amenities. With room for up to eight guests, everyone has their own private retreat onboard."
        ),
        Seed(
            title: "Intermediate Pickleball Clinic by the Palm Beach Royals x Nikki Roth",
            category: .fun,
            urlString: "https://www.palmbeachroyals.com/events",
            imageAssetName: "PickleballClinic",
            notes: "Join us for an exciting event that you won't want to miss. Experience the thrill and be part of our community."
        ),
        Seed(
            title: "Yoga Community in Boca Raton",
            category: .fun,
            urlString: "https://yogajourney.com/yjcommunity",
            imageAssetName: "YogaJourney",
            notes: "Yoga Journey has always been about community, and we're grateful for everyone who has been part of ours. If you've practiced with us, we'd love to hear about your experience."
        ),
        Seed(
            title: "Le Colonial Delray Beach",
            category: .eats,
            urlString: "https://www.lecolonial.com/delray-beach/",
            imageAssetName: "LeColonial",
            notes: """
            Timeless fine dining.
            Famed Vietnamese fare.

            Situated in Delray’s lively beachfront town square, Le Colonial transports guests to a different time and place, an era of romance and soft architecture–old world French glamour and vivid flavor. Our warm, romantic atmosphere seamlessly blends indoor and outdoor spaces, creating a vibrant yet relaxed ambiance that harmonizes with the local culture.
            """
        ),
        Seed(
            title: "Easy Homemade Sauerkraut (Fermented Cabbage)",
            category: .eats,
            urlString: "https://www.instagram.com/p/DVrPo6nETT7/",
            imageAssetName: "Sauerkraut",
            notes: """
            Ingredients:
            • 1 kg green cabbage, thinly sliced
            • 50 g carrots, grated
            • 20 g salt (non-iodized)
            Instructions
            1. Thinly slice the cabbage (a mandolin slicer makes this much easier).
            2. Add the grated carrots and salt.
            3. Gently mix everything together with your hands until the cabbage begins releasing some moisture.
            4. Pack the cabbage tightly into a clean jar.
            5. Press it down so the cabbage is fully submerged in its natural brine.
            6. Leave the jar on the counter to ferment for 4 days, releasing trapped air once a day.
            7. Move it to the fridge and enjoy your homemade sauerkraut.
            #sauerkraut #fermentedfoods #guthealthrecipes
            """
        ),
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
