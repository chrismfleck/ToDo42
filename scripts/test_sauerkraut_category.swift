import Foundation

// Standalone copy of SampleData.misfiledSauerkrautCategories for logic testing
// on Linux (the app target requires Xcode). Keep in sync with ToDo42/ToDoItem.swift.

enum ItemCategory: String, Equatable {
    case places, fun, eats, projects, recipe
}

struct Seed {
    let title: String
    let category: ItemCategory
    let imageAssetName: String
}

let seeds: [Seed] = [
    Seed(title: "Le Colonial Delray Beach", category: .eats, imageAssetName: "LeColonial"),
    Seed(
        title: "Easy Homemade Sauerkraut (Fermented Cabbage)",
        category: .recipe,
        imageAssetName: "Sauerkraut"
    ),
]

func misfiledSauerkrautCategories(title: String, categories: [ItemCategory]) -> [ItemCategory]? {
    guard let seed = seeds.first(where: { $0.imageAssetName == "Sauerkraut" }) else { return nil }
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard name == seed.title else { return nil }
    guard categories == [.eats], seed.category != .eats else { return nil }
    return [seed.category]
}

var failures = 0

func expect(_ label: String, _ got: [ItemCategory]?, _ want: [ItemCategory]?) {
    let ok = got == want
    if !ok { failures += 1 }
    let mark = ok ? "ok" : "FAIL"
    print("\(mark) \(label) got=\(String(describing: got)) want=\(String(describing: want))")
}

let title = "Easy Homemade Sauerkraut (Fermented Cabbage)"

expect("preload still on Table 4 Two", misfiledSauerkrautCategories(title: title, categories: [.eats]), [.recipe])
expect("leading space still matches", misfiledSauerkrautCategories(title: "  \(title)  ", categories: [.eats]), [.recipe])
expect("already on Recipe", misfiledSauerkrautCategories(title: title, categories: [.recipe]), nil)
expect("user added another tab", misfiledSauerkrautCategories(title: title, categories: [.eats, .fun]), nil)
expect("other sample stays on Table", misfiledSauerkrautCategories(title: "Le Colonial Delray Beach", categories: [.eats]), nil)
expect("different title stays", misfiledSauerkrautCategories(title: "Homemade sauerkraut", categories: [.eats]), nil)

if failures == 0 {
    print("\nALL TESTS PASSED")
} else {
    print("\n\(failures) TEST(S) FAILED")
    exit(1)
}
