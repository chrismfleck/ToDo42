import Foundation

// Standalone copies of the CloudKit catalog/tombstone helpers for logic testing
// on Linux (the app target needs Xcode). Keep in sync with
// ToDo42/CloudKitValues.swift (enum RemoteItemApply / CloudKitValues).
enum CloudKitValues {
    static func mergedItemIDs(_ a: String?, _ b: [String]) -> String {
        var ids = Set((a ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty })
        for id in b where !id.isEmpty { ids.insert(id) }
        return ids.sorted().joined(separator: ",")
    }

    static func removingItemID(_ catalog: String?, _ itemID: String) -> String {
        (catalog ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { $0 != itemID && !$0.isEmpty }
            .sorted()
            .joined(separator: ",")
    }
}

enum RemoteItemApply {
    static func isTombstone(notifyKind: String?) -> Bool {
        (notifyKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "delete"
    }
    static func shouldSkipSaveOverTombstone(existingNotifyKind: String?) -> Bool {
        isTombstone(notifyKind: existingNotifyKind)
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

print(failures == 0 ? "\nALL SYNC CATALOG TESTS PASSED" : "\n\(failures) TEST(S) FAILED")
if failures != 0 { exit(1) }
