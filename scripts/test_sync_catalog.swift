import Foundation

// Standalone copies of the CloudKit catalog/tombstone helpers for logic testing
// on Linux (the app target needs Xcode). Keep in sync with
// ToDo42/CloudKitValues.swift (enum RemoteItemApply / CloudKitValues).
enum CloudKitValues {
    static let deletedMark = "x:"

    static func isDeletedMark(_ token: String) -> Bool {
        token.hasPrefix(deletedMark)
    }

    static func markedDeletedID(_ token: String) -> String? {
        guard isDeletedMark(token) else { return nil }
        let id = String(token.dropFirst(deletedMark.count))
        return id.isEmpty ? nil : id
    }

    static func deletedIDs(in catalog: String?) -> [String] {
        (catalog ?? "")
            .split(separator: ",")
            .compactMap { markedDeletedID(String($0)) }
    }

    static func liveItemIDs(in catalog: String?) -> [String] {
        (catalog ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty && markedDeletedID($0) == nil }
    }

    static func markDeleted(_ catalog: String?, ids: [String], cap: Int = 500) -> String {
        let drop = Set(ids.filter { !$0.isEmpty })
        let live = liveItemIDs(in: catalog).filter { !drop.contains($0) }
        var deleted = deletedIDs(in: catalog)
        var seen = Set(deleted)
        for id in ids where !id.isEmpty && !seen.contains(id) {
            deleted.append(id)
            seen.insert(id)
        }
        if deleted.count > cap { deleted = Array(deleted.suffix(cap)) }
        return (live.sorted() + deleted.map { deletedMark + $0 }).joined(separator: ",")
    }

    static func mergedItemIDs(_ a: String?, _ b: [String]) -> String {
        let deleted = Set(deletedIDs(in: a))
        var ids = Set(liveItemIDs(in: a))
        for id in b where !id.isEmpty && !deleted.contains(id) && markedDeletedID(id) == nil {
            ids.insert(id)
        }
        let marks = deletedIDs(in: a).map { deletedMark + $0 }
        return (ids.sorted() + marks).joined(separator: ",")
    }

    static func deletionURLKey(_ urlString: String?) -> String? {
        let trimmed = (urlString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return trimmed.lowercased()
        }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if bare == "youtu.be" {
            let video = url.path.split(separator: "/").first.map(String.init) ?? ""
            if !video.isEmpty { return "yt:\(video)" }
        }
        if bare == "youtube.com" || bare == "m.youtube.com" || bare == "music.youtube.com" {
            if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               let video = items.first(where: { $0.name == "v" })?.value, !video.isEmpty {
                return "yt:\(video)"
            }
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]), !parts[1].isEmpty {
                return "yt:\(parts[1])"
            }
        }
        var text = trimmed.lowercased()
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    static func removingItemID(_ catalog: String?, _ itemID: String) -> String {
        (catalog ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { $0 != itemID && !$0.isEmpty }
            .sorted()
            .joined(separator: ",")
    }

    static func mergedDeletedIDs(_ existing: String?, adding: [String], cap: Int = 500) -> String {
        var ids = (existing ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
        var seen = Set(ids)
        for id in adding where !id.isEmpty && !seen.contains(id) {
            ids.append(id)
            seen.insert(id)
        }
        if ids.count > cap { ids = Array(ids.suffix(cap)) }
        return ids.joined(separator: ",")
    }
}

enum RemoteItemApply {
    static func isTombstone(notifyKind: String?) -> Bool {
        (notifyKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "delete"
    }
    static func shouldSkipSaveOverTombstone(existingNotifyKind: String?) -> Bool {
        isTombstone(notifyKind: existingNotifyKind)
    }
    static func isOwnEdit(lastEditor: String?, myRole: String?) -> Bool {
        let editor = (lastEditor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if editor.isEmpty { return true }
        return editor == (myRole ?? "")
    }
    static func isProvisionalCatalogAdd(
        notifyKind: String?,
        createdAt: Date,
        now: Date = Date(),
        recentSeconds: TimeInterval = 48 * 3600
    ) -> Bool {
        let kind = (notifyKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if kind == "add" { return true }
        if kind == "delete" { return false }
        return now.timeIntervalSince(createdAt) < recentSeconds
    }
    static func shouldCreateMissingRecord(allowCreate: Bool, notifyKind: String, title: String) -> Bool {
        if allowCreate { return true }
        let kind = notifyKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !kind.isEmpty, kind != "delete" else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || kind == "heart"
            || kind == "reorder"
    }
    static func canJoinExistingPair(myName: String, hostName: String, guestName: String) -> Bool {
        _ = hostName
        let me = myName.trimmingCharacters(in: .whitespacesAndNewlines)
        let guest = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        if guest.isEmpty { return true }
        guard !me.isEmpty else { return false }
        return me.caseInsensitiveCompare(guest) == .orderedSame
    }
}

var failures = 0
func expect(_ label: String, _ got: String, _ want: String) {
    let ok = got == want
    if !ok { failures += 1 }
    print("\(ok ? "ok  " : "FAIL") \(label)\n     got  = \"\(got)\"\n     want = \"\(want)\"")
}
func expectBool(_ label: String, _ got: Bool, _ want: Bool) {
    let ok = got == want
    if !ok { failures += 1 }
    print("\(ok ? "ok  " : "FAIL") \(label) = \(got) (want \(want))")
}

print("== mergedItemIDs: concurrent adds must not lose either side ==")
// Device A's catalog had A,B. We add C. Merge keeps all three (sorted).
expect("add C to A,B", CloudKitValues.mergedItemIDs("A,B", ["C"]), "A,B,C")
// The classic lost-update: partner already added D remotely; our merge preserves D.
expect("add C when server already has A,B,D", CloudKitValues.mergedItemIDs("A,B,D", ["C"]), "A,B,C,D")
expect("idempotent re-add", CloudKitValues.mergedItemIDs("A,B,C", ["B"]), "A,B,C")
expect("empty base", CloudKitValues.mergedItemIDs("", ["X"]), "X")

print("\n== removingItemID: removing one id keeps a concurrently-added id ==")
// Server now has A,B,C (partner just added C). We remove B. C must survive.
expect("remove B from A,B,C", CloudKitValues.removingItemID("A,B,C", "B"), "A,C")
expect("remove missing id", CloudKitValues.removingItemID("A,C", "B"), "A,C")
expect("remove last", CloudKitValues.removingItemID("B", "B"), "")

print("\n== tombstone guard: a re-push must never overwrite a delete ==")
expectBool("existing is delete", RemoteItemApply.shouldSkipSaveOverTombstone(existingNotifyKind: "delete"), true)
expectBool("existing is DELETE (case)", RemoteItemApply.shouldSkipSaveOverTombstone(existingNotifyKind: " Delete "), true)
expectBool("existing is normal edit", RemoteItemApply.shouldSkipSaveOverTombstone(existingNotifyKind: ""), false)
expectBool("existing is reorder", RemoteItemApply.shouldSkipSaveOverTombstone(existingNotifyKind: "reorder"), false)
expectBool("existing is nil", RemoteItemApply.shouldSkipSaveOverTombstone(existingNotifyKind: nil), false)

print("\n== shouldCreateMissingRecord: catch-up must not resurrect deletes ==")
expectBool(
    "catch-up empty kind + title",
    RemoteItemApply.shouldCreateMissingRecord(allowCreate: false, notifyKind: "", title: "Old Cabin"),
    false
)
expectBool(
    "explicit add",
    RemoteItemApply.shouldCreateMissingRecord(allowCreate: false, notifyKind: "add", title: "New Cabin"),
    true
)
expectBool(
    "allowCreate restore",
    RemoteItemApply.shouldCreateMissingRecord(allowCreate: true, notifyKind: "", title: "Restored"),
    true
)

print("\n== canJoinExistingPair: third person must not take the guest seat ==")
expectBool(
    "open guest seat",
    RemoteItemApply.canJoinExistingPair(myName: "Diane", hostName: "Chris", guestName: ""),
    true
)
expectBool(
    "same guest rejoin",
    RemoteItemApply.canJoinExistingPair(myName: "Deena", hostName: "Chris", guestName: "Deena"),
    true
)
expectBool(
    "case-insensitive guest rejoin",
    RemoteItemApply.canJoinExistingPair(myName: "deena", hostName: "Chris", guestName: "Deena"),
    true
)
expectBool(
    "third person blocked",
    RemoteItemApply.canJoinExistingPair(myName: "Diane", hostName: "Chris", guestName: "Deena"),
    false
)
expectBool(
    "empty joiner name blocked when seat taken",
    RemoteItemApply.canJoinExistingPair(myName: "", hostName: "Chris", guestName: "Deena"),
    false
)

print("\n== isOwnEdit: our own catalog-orphans are healed, not deleted ==")
expectBool("empty editor = mine", RemoteItemApply.isOwnEdit(lastEditor: "", myRole: "chris"), true)
expectBool("nil editor = mine", RemoteItemApply.isOwnEdit(lastEditor: nil, myRole: "chris"), true)
expectBool("same role = mine", RemoteItemApply.isOwnEdit(lastEditor: "chris", myRole: "chris"), true)
expectBool("padded same role = mine", RemoteItemApply.isOwnEdit(lastEditor: " chris ", myRole: "chris"), true)
expectBool("partner role = not mine", RemoteItemApply.isOwnEdit(lastEditor: "deena", myRole: "chris"), false)

print("\n== isProvisionalCatalogAdd: partner must accept raced new adds ==")
let now = Date()
expectBool(
    "notifyKind add",
    RemoteItemApply.isProvisionalCatalogAdd(notifyKind: "add", createdAt: now.addingTimeInterval(-200_000), now: now),
    true
)
expectBool(
    "recent empty kind",
    RemoteItemApply.isProvisionalCatalogAdd(notifyKind: "", createdAt: now.addingTimeInterval(-60), now: now),
    true
)
expectBool(
    "old empty kind ignored",
    RemoteItemApply.isProvisionalCatalogAdd(notifyKind: "", createdAt: now.addingTimeInterval(-200_000), now: now),
    false
)
expectBool(
    "delete never provisional",
    RemoteItemApply.isProvisionalCatalogAdd(notifyKind: "delete", createdAt: now, now: now),
    false
)

print("\n== mergedDeletedIDs: co-writable authoritative delete list ==")
expect("add new deleted id", CloudKitValues.mergedDeletedIDs("A,B", adding: ["C"]), "A,B,C")
expect("dedupe existing", CloudKitValues.mergedDeletedIDs("A,B", adding: ["B"]), "A,B")
expect("empty base", CloudKitValues.mergedDeletedIDs("", adding: ["X"]), "X")
// Cap keeps the most recently deleted ids (insertion order preserved).
expect("cap keeps most recent", CloudKitValues.mergedDeletedIDs("A,B,C", adding: ["D"], cap: 2), "C,D")

print("\n== markDeleted: x: marks live in itemIDs and are not resurrected ==")
expect("mark B deleted", CloudKitValues.markDeleted("A,B,C", ids: ["B"]), "A,C,x:B")
expect("mark keeps older marks", CloudKitValues.markDeleted("A,C,x:B", ids: ["A"]), "C,x:B,x:A")
expect(
    "merge must not re-add a marked id",
    CloudKitValues.mergedItemIDs("A,C,x:B", ["B", "D"]),
    "A,C,D,x:B"
)
expect("live ids ignore marks", CloudKitValues.liveItemIDs(in: "A,C,x:B").joined(separator: ","), "A,C")

print("\n== deletionURLKey: same YouTube video, different share links ==")
expect(
    "watch url",
    CloudKitValues.deletionURLKey("https://www.youtube.com/watch?v=dQw4w9WgXcQ") ?? "",
    "yt:dQw4w9WgXcQ"
)
expect(
    "short url",
    CloudKitValues.deletionURLKey("https://youtu.be/dQw4w9WgXcQ") ?? "",
    "yt:dQw4w9WgXcQ"
)
expectBool(
    "same video",
    CloudKitValues.deletionURLKey("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        == CloudKitValues.deletionURLKey("https://youtu.be/dQw4w9WgXcQ"),
    true
)
expectBool(
    "different video",
    CloudKitValues.deletionURLKey("https://youtu.be/aaaaaaaaaaa")
        == CloudKitValues.deletionURLKey("https://youtu.be/dQw4w9WgXcQ"),
    false
)

print(failures == 0 ? "\nALL SYNC CATALOG TESTS PASSED" : "\n\(failures) TEST(S) FAILED")
if failures != 0 { exit(1) }
