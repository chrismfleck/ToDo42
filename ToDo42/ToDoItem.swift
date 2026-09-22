import Foundation
import SwiftData
import SwiftUI

enum ItemCategory: String, CaseIterable, Identifiable {
    case places, fun, eats, projects, recipe, health, vegasTrip, londonTrip, dcTrip
    var id: String { rawValue }

    static let primaryPage: [ItemCategory] = [.places, .fun, .eats]
    static let middlePage: [ItemCategory] = [.projects, .recipe, .health]
    static let tripsPage: [ItemCategory] = [.vegasTrip, .londonTrip, .dcTrip]
    /// Legacy name — same tabs as `middlePage`.
    static let extraPage: [ItemCategory] = middlePage

    static let pages: [[ItemCategory]] = [primaryPage, middlePage, tripsPage]

    var pageIndex: Int {
        if Self.tripsPage.contains(self) { return 2 }
        if Self.middlePage.contains(self) { return 1 }
        return 0
    }

    var defaultTitle: String {
        switch self {
        case .places: "Bed 4 Two"
        case .fun: "Fun 4 Two"
        case .eats: "Table 4 Two"
        case .projects: "Projects 4 Two"
        case .recipe: "Recipe 4 Two"
        case .health: "Health Tips 4 Two"
        case .vegasTrip: "Vegas Trip 4 Two"
        case .londonTrip: "London Trip 4 Two"
        case .dcTrip: "DC Trip 4 Two"
        }
    }

    @MainActor
    var title: String { CategoryNames.shared.title(for: self) }

    var systemImage: String {
        switch self {
        case .places: "bed.double.fill"
        case .fun: "sailboat.fill"
        case .eats: "fork.knife"
        case .projects: "house.fill"
        case .recipe: "frying.pan.fill"
        case .health: "heart.text.square.fill"
        case .vegasTrip, .londonTrip, .dcTrip: "airplane"
        }
    }

    var iconColor: Color {
        switch self {
        case .places, .health:
            Color(red: 0.90, green: 0.20, blue: 0.22)
        case .fun:
            Color(red: 0.95, green: 0.76, blue: 0.08)
        case .eats, .recipe:
            Color(red: 0.16, green: 0.67, blue: 0.30)
        case .projects:
            Color(red: 0.20, green: 0.55, blue: 0.85)
        case .vegasTrip, .londonTrip, .dcTrip:
            Color(red: 0.56, green: 0.27, blue: 0.85)
        }
    }

    static func parse(_ raw: String) -> [ItemCategory] {
        var seen = Set<ItemCategory>()
        var ordered: [ItemCategory] = []
        for part in raw.split(separator: ",") {
            let token = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let cat: ItemCategory?
            if token == "trip" {
                // Pre–Projects rename: old Trip 4 Two tab.
                cat = .projects
            } else {
                cat = ItemCategory(rawValue: token)
            }
            guard let cat, seen.insert(cat).inserted else { continue }
            ordered.append(cat)
        }
        return ordered.isEmpty ? [.places] : ordered
    }

    static func encode(_ cats: [ItemCategory]) -> String {
        var seen = Set<ItemCategory>()
        var ordered: [ItemCategory] = []
        for cat in cats where seen.insert(cat).inserted {
            ordered.append(cat)
        }
        if ordered.isEmpty { ordered = [.places] }
        return ordered.map(\.rawValue).joined(separator: ",")
    }

    static func guessed(urlString: String, title: String) -> ItemCategory {
        let haystack = "\(urlString) \(title)".lowercased()
        if haystack.contains("airbnb") || haystack.contains("vrbo") || haystack.contains("hotel") || haystack.contains("maps.apple") {
            return .places
        }
        if haystack.contains("allrecipes")
            || haystack.contains("nytimes.com/cooking")
            || haystack.contains("recipe")
            || haystack.contains("ingredients") {
            return .recipe
        }
        if haystack.contains("yelp")
            || haystack.contains("opentable")
            || haystack.contains("restaurant") {
            return .eats
        }
        if haystack.contains("webmd")
            || haystack.contains("healthline")
            || haystack.contains("health tip")
            || haystack.contains("wellness") {
            return .health
        }
        if haystack.contains("vegas") || haystack.contains("las vegas") {
            return .vegasTrip
        }
        if haystack.contains("london") {
            return .londonTrip
        }
        if haystack.contains("washington")
            || haystack.contains("washington dc")
            || haystack.contains("washington, dc")
            || haystack.contains("/dc/")
            || haystack.contains(" dc ") {
            return .dcTrip
        }
        if haystack.contains("tripadvisor")
            || haystack.contains("expedia")
            || haystack.contains("kayak.com")
            || haystack.contains("google.com/travel") {
            return .vegasTrip
        }
        if haystack.contains("home depot")
            || haystack.contains("lowes")
            || haystack.contains("ikea")
            || haystack.contains("project")
            || haystack.contains("renovat") {
            return .projects
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
    var extraImageData2: Data? = nil
    var extraImageData3: Data? = nil
    var notes: String = ""
    var chrisHearted: Bool = false
    var deenaHearted: Bool = false
    var categoryRaw: String
    var isDone: Bool
    var createdAt: Date
    var sortOrder: Int = 0
    var updatedAt: Date?
    var lastEditor: String = ""
    var placeLatitude: Double?
    var placeLongitude: Double?
    var placeLocality: String?
    var placeSource: String?
    /// CloudKit list this row belongs to. Empty until migrated / stamped.
    var pairID: String = ""

    init(
        title: String,
        category: ItemCategory,
        categories: [ItemCategory]? = nil,
        urlString: String? = nil,
        imageAssetName: String? = nil,
        imageURLString: String? = nil,
        imageData: Data? = nil,
        extraImageData: Data? = nil,
        extraImageData2: Data? = nil,
        extraImageData3: Data? = nil,
        notes: String = "",
        sortOrder: Int = 0,
        pairID: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.categoryRaw = ItemCategory.encode(categories ?? [category])
        self.urlString = urlString
        self.imageAssetName = imageAssetName
        self.imageURLString = imageURLString
        self.imageData = imageData
        self.extraImageData = extraImageData
        self.extraImageData2 = extraImageData2
        self.extraImageData3 = extraImageData3
        self.notes = notes
        self.chrisHearted = false
        self.deenaHearted = false
        self.isDone = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortOrder = sortOrder
        self.lastEditor = ""
        // Callers on the main actor stamp the active pair; do not read PairSession here
        // (init is nonisolated and PairSession is @MainActor).
        self.pairID = pairID ?? ""
    }

    var category: ItemCategory {
        get { categories.first ?? .places }
        set {
            var next = categories.filter { $0 != newValue }
            next.insert(newValue, at: 0)
            categories = next
        }
    }

    var categories: [ItemCategory] {
        get { ItemCategory.parse(categoryRaw) }
        set { categoryRaw = ItemCategory.encode(newValue) }
    }

    func belongs(to category: ItemCategory) -> Bool {
        categories.contains(category)
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

    var hasExtraPhoto2: Bool {
        if let data = extraImageData2, !data.isEmpty { return true }
        return false
    }

    var hasExtraPhoto3: Bool {
        if let data = extraImageData3, !data.isEmpty { return true }
        return false
    }

    var photoCount: Int {
        (hasPhoto ? 1 : 0) + (hasExtraPhoto ? 1 : 0) + (hasExtraPhoto2 ? 1 : 0) + (hasExtraPhoto3 ? 1 : 0)
    }

    var hasAnyPhotos: Bool { photoCount > 0 }
}

enum ItemStore {
    static func allItems(in context: ModelContext) -> [TodoItem] {
        (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
    }

    static func items(forPair pairID: String?, in context: ModelContext) -> [TodoItem] {
        let all = allItems(in: context)
        guard let pairID, !pairID.isEmpty else { return all }
        return all.filter { $0.pairID == pairID || $0.pairID.isEmpty }
    }

    /// Assign legacy rows with no pair tag to the active pair so sync cannot wipe other lists.
    @MainActor
    static func migrateUnscopedItems(in context: ModelContext, to pairID: String?) {
        guard let pairID, !pairID.isEmpty else { return }
        var changed = false
        for item in allItems(in: context) where item.pairID.isEmpty {
            item.pairID = pairID
            changed = true
        }
        if changed {
            try? context.save()
        }
    }

    /// Drop blank-title companion ghosts that used to appear as duplicate tiles.
    @MainActor
    static func purgeBlankTitleGhosts(in context: ModelContext) {
        var didDelete = false
        for item in allItems(in: context) {
            let blank = item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard blank else { continue }
            context.delete(item)
            didDelete = true
        }
        if didDelete {
            try? context.save()
        }
    }

    /// Collapse same-title + same-link copies within a pair (sync ghosts).
    @MainActor
    static func deduplicateContentTwins(in context: ModelContext) {
        let items = allItems(in: context)
        var groups: [String: [TodoItem]] = [:]
        for item in items {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !title.isEmpty else { continue }
            let url = (item.urlString ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !url.isEmpty else { continue }
            let key = "\(item.pairID)|\(title)|\(url)"
            groups[key, default: []].append(item)
        }
        var didDelete = false
        for copies in groups.values where copies.count > 1 {
            let ranked = copies.sorted { lhs, rhs in
                if lhs.photoCount != rhs.photoCount { return lhs.photoCount > rhs.photoCount }
                if lhs.notes.count != rhs.notes.count { return lhs.notes.count > rhs.notes.count }
                let l = lhs.updatedAt ?? lhs.createdAt
                let r = rhs.updatedAt ?? rhs.createdAt
                return l > r
            }
            let keep = ranked[0]
            for extra in ranked.dropFirst() {
                keep.chrisHearted = keep.chrisHearted || extra.chrisHearted
                keep.deenaHearted = keep.deenaHearted || extra.deenaHearted
                if keep.imageData == nil, let data = extra.imageData, !data.isEmpty {
                    keep.imageData = data
                }
                if keep.extraImageData == nil, let data = extra.extraImageData, !data.isEmpty {
                    keep.extraImageData = data
                }
                if keep.extraImageData2 == nil, let data = extra.extraImageData2, !data.isEmpty {
                    keep.extraImageData2 = data
                }
                if keep.extraImageData3 == nil, let data = extra.extraImageData3, !data.isEmpty {
                    keep.extraImageData3 = data
                }
                if keep.notes.isEmpty, !extra.notes.isEmpty {
                    keep.notes = extra.notes
                }
                context.delete(extra)
                didDelete = true
            }
        }
        if didDelete {
            try? context.save()
        }
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
            if keep.extraImageData2 == nil, let data = extra.extraImageData2, data.isEmpty == false {
                keep.extraImageData2 = data
            }
            if keep.extraImageData3 == nil, let data = extra.extraImageData3, data.isEmpty == false {
                keep.extraImageData3 = data
            }
            context.delete(extra)
        }
        try? context.save()
    }

    static func deduplicateSampleCopies(in context: ModelContext) {
        let sampleTitles = Set(SampleData.seeds.map(\.title)).union([
            "Lake Escape 2",
            "Greek Seas Charter Sailing",
            "Keto recipe",
        ])
        let items = allItems(in: context)
        var groups: [String: [TodoItem]] = [:]
        for item in items {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard sampleTitles.contains(title) else { continue }
            groups[title, default: []].append(item)
        }
        var didDelete = false
        for copies in groups.values where copies.count > 1 {
            let ranked = copies.sorted { lhs, rhs in
                if lhs.hasPhoto != rhs.hasPhoto { return lhs.hasPhoto }
                if lhs.notes.count != rhs.notes.count { return lhs.notes.count > rhs.notes.count }
                return lhs.createdAt < rhs.createdAt
            }
            let keep = ranked[0]
            for extra in ranked.dropFirst() {
                keep.chrisHearted = keep.chrisHearted || extra.chrisHearted
                keep.deenaHearted = keep.deenaHearted || extra.deenaHearted
                if keep.imageData == nil, let data = extra.imageData, data.isEmpty == false {
                    keep.imageData = data
                }
                if keep.extraImageData == nil, let data = extra.extraImageData, data.isEmpty == false {
                    keep.extraImageData = data
                }
                if keep.extraImageData2 == nil, let data = extra.extraImageData2, data.isEmpty == false {
                    keep.extraImageData2 = data
                }
                if keep.extraImageData3 == nil, let data = extra.extraImageData3, data.isEmpty == false {
                    keep.extraImageData3 = data
                }
                if keep.imageAssetName == nil || keep.imageAssetName?.isEmpty == true,
                   let name = extra.imageAssetName, name.isEmpty == false {
                    keep.imageAssetName = name
                }
                context.delete(extra)
                didDelete = true
            }
        }
        if didDelete {
            try? context.save()
        }
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
            urlString: "https://www.airbnb.com/rooms/1660244481236892848",
            imageAssetName: "BarnLoft",
            notes: "Escape to a one-of-a-kind private lakefront barn loft on peaceful farmland in Dade City. Designed with dreamy Victorian style, antique character, and a romantic high-end boutique feel, this stay blends rustic charm with elevated comfort. Unwind in the silo jacuzzi, enjoy slow mornings on the deck beneath the trees, watch movies on the large-screen projector, and meet our friendly farm animals for a magical agritourism escape that feels private, special, and luxurious."
        ),
        Seed(
            title: "Eco-Luxurious Lakefront haven (Fire pit & Hot Tub)",
            category: .places,
            urlString: "https://www.airbnb.com/rooms/976091434015163591",
            imageAssetName: "EcoLuxHaven",
            notes: """
            Experience the perfect blend of an eco-friendly retreat and modern luxury of our lakefront container home. Nestled in the heart of nature, this stylish oasis promises an unforgettable experience where you can immerse yourself amidst the beauty of the countryside without sacrificing comfort. Plus, enjoy the opportunity to interact with our farm animals, adding a touch of rural charm to your agritourism escape.

            Also, feel free to check out  my other listing, Casa de Elvira on my host profile.
            """
        ),
        Seed(
            title: "Historic 1974 Trawler on the River",
            category: .places,
            urlString: "https://www.airbnb.com/rooms/1711681767125004425",
            imageAssetName: "HistoricTrawler",
            notes: "Stay aboard a classic 1974 trawler on the beautiful St. Johns River. Relax on the spacious upper deck, enjoy stunning Florida sunsets, and experience a unique waterfront escape filled with charm, comfort, and unforgettable views."
        ),
        Seed(
            title: "Sunset on a Historic 1966 Sailboat",
            category: .places,
            urlString: "https://www.airbnb.com/rooms/1690972441082730451",
            imageAssetName: "HistoricSailboat",
            notes: "Stay aboard a beautifully preserved 1966 sailboat in a peaceful marina setting. Enjoy river views, stunning sunsets, vintage charm, and a unique overnight experience. Guests also have access to a complimentary tandem kayak and a waterfront restaurant just steps away."
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

    static func makeItem(_ seed: Seed, sortOrder: Int = 0, pairID: String? = nil) -> TodoItem {
        TodoItem(
            title: seed.title,
            category: seed.category,
            urlString: seed.urlString,
            imageAssetName: seed.imageAssetName,
            notes: seed.notes,
            sortOrder: sortOrder,
            pairID: pairID
        )
    }
}
