import Foundation

// Standalone copy of PageMetadata.isPlaceholderTitle for logic testing on Linux
// (the app target itself requires Xcode/UIKit). Keep in sync with
// ShareExtension/PageMetadata.swift and ToDo42/PageMetadata.swift.
enum PageMetadata {
    static func isPlaceholderTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return true }
        let placeholders: Set<String> = [
            "shared item",
            "airbnb stay",
            "instagram",
            "tiktok",
            "x post",
            "facebook",
            "youtube",
            "pinterest",
            "airbnb.com",
            "www.airbnb.com",
            "instagram.com",
            "www.instagram.com",
            "tiktok.com",
            "www.tiktok.com",
            "vm.tiktok.com",
            "vt.tiktok.com",
            "youtube.com",
            "www.youtube.com",
            "m.youtube.com",
            "youtu.be",
            "pinterest.com",
            "www.pinterest.com",
            "pin.it",
        ]
        if placeholders.contains(trimmed) { return true }
        if trimmed.hasSuffix(".com") && !trimmed.contains(" ") { return true }
        // Generic share-sheet boilerplate that carries no real title
        // (e.g. Pinterest shares arrive titled "Take a Look !").
        let condensed = trimmed
            .replacingOccurrences(of: #"[\s!.]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let boilerplate: Set<String> = [
            "take a look",
            "check this out",
            "check it out",
        ]
        if boilerplate.contains(condensed) { return true }
        return false
    }
}

var failures = 0
func expect(_ title: String, _ want: Bool) {
    let got = PageMetadata.isPlaceholderTitle(title)
    let mark = got == want ? "ok  " : "FAIL"
    if got != want { failures += 1 }
    print("\(mark) isPlaceholderTitle(\"\(title)\") = \(got) (want \(want))")
}

print("== Pinterest boilerplate (should be placeholders → get replaced by real title) ==")
expect("Take a Look !", true)
expect("Take a Look!", true)
expect("Take a Look", true)
expect("take a look !", true)
expect("Pinterest", true)
expect("pin.it", true)
expect("pinterest.com", true)

print("\n== YouTube (should be placeholders → get replaced by real title) ==")
expect("YouTube", true)
expect("youtube", true)
expect("youtu.be", true)
expect("youtube.com", true)
expect("m.youtube.com", true)

print("\n== Real titles (must NOT be placeholders → keep them) ==")
expect("Lake Como guide", false)
expect("Cool Barn in Dade City Florida", false)
expect("How to make sourdough | full recipe", false)
expect("Take a look at this cabin on the lake", false) // longer real sentence, not exact boilerplate
expect("Rick Astley - Never Gonna Give You Up (Official Video)", false)
expect("10 best hikes near Seattle", false)

print("\n== Existing placeholders still detected ==")
expect("", true)
expect("Shared item", true)
expect("Instagram", true)
expect("airbnb.com", true)

if failures == 0 {
    print("\nALL TESTS PASSED")
} else {
    print("\n\(failures) TEST(S) FAILED")
    exit(1)
}
