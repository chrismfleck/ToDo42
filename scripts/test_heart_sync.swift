import Foundation

enum PairRole: String {
    case chris
    case deena
}

enum CloudKitValues {
    static func flag(_ value: Any?) -> Bool {
        guard let value else { return false }
        if let number = value as? NSNumber { return number.intValue != 0 }
        if let flag = value as? Bool { return flag }
        if let int = value as? Int { return int != 0 }
        if let int64 = value as? Int64 { return int64 != 0 }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed == "1" || trimmed == "true" || trimmed == "yes"
        }
        return false
    }
}

enum PartnerHeartMerge {
    static func partnerJustHearted(
        myRole: PairRole?,
        localChris: Bool,
        localDeena: Bool,
        remoteChris: Bool,
        remoteDeena: Bool
    ) -> Bool {
        switch myRole {
        case .deena:
            return remoteChris && remoteChris != localChris
        case .chris, nil:
            return remoteDeena && remoteDeena != localDeena
        }
    }

    static func mergedChris(
        myRole: PairRole?,
        localChris: Bool,
        remoteChris: Bool
    ) -> Bool {
        myRole == .chris ? localChris : remoteChris
    }

    static func mergedDeena(
        myRole: PairRole?,
        localDeena: Bool,
        remoteDeena: Bool
    ) -> Bool {
        myRole == .deena ? localDeena : remoteDeena
    }
}

var failed = 0
func expect(_ condition: Bool, _ name: String) {
    if condition {
        print("PASS \(name)")
    } else {
        failed += 1
        print("FAIL \(name)")
    }
}

expect(CloudKitValues.flag(nil) == false, "nil is not hearted")
expect(CloudKitValues.flag(NSNumber(value: 1)) == true, "NSNumber 1 is hearted")
expect(CloudKitValues.flag(NSNumber(value: 0)) == false, "NSNumber 0 is not hearted")
expect(CloudKitValues.flag(Int64(1)) == true, "Int64 1 is hearted")
expect(CloudKitValues.flag(1) == true, "Int 1 is hearted")
expect(CloudKitValues.flag(true) == true, "Bool true is hearted")
expect(CloudKitValues.flag("1") == true, "String 1 is hearted")

expect(
    PartnerHeartMerge.partnerJustHearted(
        myRole: .chris,
        localChris: false,
        localDeena: false,
        remoteChris: false,
        remoteDeena: true
    ),
    "Chris is notified when Deena hearts"
)
expect(
    PartnerHeartMerge.mergedDeena(myRole: .chris, localDeena: false, remoteDeena: true) == true,
    "Chris keeps Deena heart from the server"
)
expect(
    PartnerHeartMerge.mergedChris(myRole: .chris, localChris: true, remoteChris: false) == true,
    "Chris does not let a stale server wipe his own heart"
)
expect(
    PartnerHeartMerge.partnerJustHearted(
        myRole: .chris,
        localChris: false,
        localDeena: true,
        remoteChris: false,
        remoteDeena: true
    ) == false,
    "No repeat notification when Deena heart is already local"
)
expect(
    PartnerHeartMerge.partnerJustHearted(
        myRole: .chris,
        localChris: false,
        localDeena: true,
        remoteChris: false,
        remoteDeena: false
    ) == false,
    "Unheart does not send a hearted notification"
)

enum ItemDuplicatePick {
    static func keepFirst(
        firstUpdated: Date,
        firstHasPhoto: Bool,
        firstNoteCount: Int,
        firstTitleEmpty: Bool = false,
        secondUpdated: Date,
        secondHasPhoto: Bool,
        secondNoteCount: Int,
        secondTitleEmpty: Bool = false
    ) -> Bool {
        if firstTitleEmpty != secondTitleEmpty { return !firstTitleEmpty }
        if firstUpdated != secondUpdated { return firstUpdated > secondUpdated }
        if firstHasPhoto != secondHasPhoto { return firstHasPhoto }
        return firstNoteCount >= secondNoteCount
    }
}

enum TDItemRecordKind: Equatable {
    case listItem
    case extraPhoto
    case unknown

    static func classify(recordName: String, title: String?, sortOrder: Int?) -> TDItemRecordKind {
        if recordName.hasPrefix("extra-") { return .extraPhoto }
        if recordName.hasPrefix("item-") { return .listItem }
        let emptyTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if sortOrder == -1, emptyTitle { return .extraPhoto }
        if emptyTitle { return .extraPhoto }
        return .listItem
    }
}

enum RemoteItemApply {
    static func resolvedTitle(localTitle: String, remoteTitle: String?) -> String {
        let trimmed = (remoteTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return localTitle }
        return remoteTitle ?? localTitle
    }

    static func shouldApplyRemoteContent(
        localUpdated: Date,
        remoteUpdated: Date,
        localTitle: String,
        remoteTitle: String?
    ) -> Bool {
        let remoteHasTitle = !(remoteTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !remoteHasTitle { return false }
        if remoteUpdated > localUpdated { return true }
        let localEmpty = localTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return localEmpty
    }

    static func shouldRepublishTitle(localTitle: String, remoteTitle: String?) -> Bool {
        let localHas = !localTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let remoteEmpty = (remoteTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return localHas && remoteEmpty
    }

    static func shouldCreateMissingRecord(allowCreate: Bool, notifyKind: String, title: String) -> Bool {
        if allowCreate || !notifyKind.isEmpty { return true }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func extraItemID(recordName: String, itemID: String?) -> String? {
        if let itemID, !itemID.isEmpty { return itemID }
        if recordName.hasPrefix("extra-") {
            return String(recordName.dropFirst("extra-".count))
        }
        return nil
    }
}

let older = Date(timeIntervalSince1970: 1)
let newer = Date(timeIntervalSince1970: 2)
expect(
    ItemDuplicatePick.keepFirst(
        firstUpdated: newer,
        firstHasPhoto: false,
        firstNoteCount: 0,
        secondUpdated: older,
        secondHasPhoto: true,
        secondNoteCount: 10
    ),
    "Keep the newer duplicate even if the older one has a photo"
)
expect(
    ItemDuplicatePick.keepFirst(
        firstUpdated: older,
        firstHasPhoto: true,
        firstNoteCount: 0,
        secondUpdated: older,
        secondHasPhoto: false,
        secondNoteCount: 40
    ),
    "If timestamps match, keep the copy with a photo"
)
expect(
    ItemDuplicatePick.keepFirst(
        firstUpdated: newer,
        firstHasPhoto: true,
        firstNoteCount: 0,
        firstTitleEmpty: true,
        secondUpdated: older,
        secondHasPhoto: false,
        secondNoteCount: 0,
        secondTitleEmpty: false
    ) == false,
    "Keep the copy that still has an item title"
)
expect(
    Dictionary([("same", 1), ("same", 2)], uniquingKeysWith: { first, _ in first })["same"] == 1,
    "Duplicate sync keys keep the first item instead of crashing"
)

func extraRecordName(for itemID: String) -> String { "extra-\(itemID)" }
let sampleID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
expect(
    extraRecordName(for: sampleID) == "extra-\(sampleID)",
    "Bottom photos use a stable companion record name"
)
expect(
    !extraRecordName(for: sampleID).hasPrefix("item-"),
    "Companion photo records are not treated as list items"
)
expect(
    TDItemRecordKind.classify(recordName: "extra-\(sampleID)", title: "", sortOrder: -1) == .extraPhoto,
    "extra- records are companion photos"
)
expect(
    TDItemRecordKind.classify(recordName: "item-\(sampleID)", title: "Lake House", sortOrder: 0) == .listItem,
    "item- records are list items"
)
expect(
    TDItemRecordKind.classify(recordName: sampleID, title: "", sortOrder: -1) == .extraPhoto,
    "Blank title plus sortOrder -1 is a companion photo even without extra- prefix"
)
expect(
    TDItemRecordKind.classify(recordName: sampleID, title: "", sortOrder: 3) == .extraPhoto,
    "Blank-title TDItem rows are not created as list items"
)
expect(
    RemoteItemApply.resolvedTitle(localTitle: "Lake House", remoteTitle: "") == "Lake House",
    "Empty companion title does not wipe the item title"
)
expect(
    RemoteItemApply.resolvedTitle(localTitle: "Lake House", remoteTitle: nil) == "Lake House",
    "Missing companion title does not wipe the item title"
)
expect(
    RemoteItemApply.shouldApplyRemoteContent(
        localUpdated: newer,
        remoteUpdated: older,
        localTitle: "",
        remoteTitle: "Lake House"
    ),
    "Pull restores a wiped title from the real item record"
)
expect(
    RemoteItemApply.shouldApplyRemoteContent(
        localUpdated: newer,
        remoteUpdated: older,
        localTitle: "Lake House",
        remoteTitle: "Cabin"
    ) == false,
    "Newer local item is not overwritten just because a companion photo exists"
)
expect(
    TDItemRecordKind.classify(recordName: "item-\(sampleID)", title: "", sortOrder: 0) == .listItem,
    "Wiped item- rows stay list items so Chris can republish the title"
)
expect(
    RemoteItemApply.shouldApplyRemoteContent(
        localUpdated: older,
        remoteUpdated: newer,
        localTitle: "Lake House",
        remoteTitle: ""
    ) == false,
    "A newer blank iCloud copy does not overwrite a local title"
)
expect(
    RemoteItemApply.shouldRepublishTitle(localTitle: "Lake House", remoteTitle: ""),
    "Chris republishes a real title over a wiped iCloud copy"
)
expect(
    RemoteItemApply.extraItemID(recordName: "extra-\(sampleID)", itemID: nil) == sampleID,
    "Companion photos map back to the item UUID"
)
expect(
    TDItemRecordKind.classify(recordName: sampleID, title: "Lake House", sortOrder: -1) == .listItem,
    "A titled row is a list item even if sortOrder is -1"
)
expect(
    RemoteItemApply.shouldCreateMissingRecord(allowCreate: false, notifyKind: "", title: "Lake House"),
    "Catch-up creates a titled item that is not yet in iCloud"
)
expect(
    RemoteItemApply.shouldCreateMissingRecord(allowCreate: false, notifyKind: "", title: "") == false,
    "Catch-up does not create a blank-title item"
)
expect(
    RemoteItemApply.shouldCreateMissingRecord(allowCreate: false, notifyKind: "add", title: "Lake House"),
    "An add upload creates the iCloud record"
)

if failed > 0 {
    fputs("\(failed) test(s) failed\n", stderr)
    exit(1)
}
print("All tests passed")
