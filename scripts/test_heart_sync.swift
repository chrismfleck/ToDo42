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

enum PartnerEditMerge {
    static func timestamp(updatedAt: Date?, modificationDate: Date?) -> Date {
        switch (updatedAt, modificationDate) {
        case let (updated?, modified?):
            return max(updated, modified)
        case let (updated?, nil):
            return updated
        case let (nil, modified?):
            return modified
        default:
            return .distantPast
        }
    }

    static func shouldApplyRemoteFields(
        myRole: PairRole?,
        localUpdated: Date,
        remoteUpdated: Date,
        localEditor: String,
        remoteEditor: String,
        contentChanged: Bool
    ) -> Bool {
        if remoteUpdated > localUpdated { return true }
        let me = myRole?.rawValue ?? ""
        guard !remoteEditor.isEmpty, remoteEditor != me else { return false }
        if localEditor == me, localUpdated > remoteUpdated { return false }
        return contentChanged || remoteUpdated >= localUpdated
    }

    static func shouldSkipCatchupPush(
        myRole: PairRole?,
        localUpdated: Date,
        remoteUpdated: Date,
        localEditor: String,
        remoteEditor: String,
        ownHeartMatches: Bool
    ) -> Bool {
        let me = myRole?.rawValue ?? ""
        if remoteUpdated > localUpdated { return true }
        if !remoteEditor.isEmpty, remoteEditor != me, remoteUpdated >= localUpdated {
            return true
        }
        if !localEditor.isEmpty, localEditor != me {
            return true
        }
        if abs(remoteUpdated.timeIntervalSince(localUpdated)) < 1 {
            return ownHeartMatches
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
        secondUpdated: Date,
        secondHasPhoto: Bool,
        secondNoteCount: Int
    ) -> Bool {
        if firstUpdated != secondUpdated { return firstUpdated > secondUpdated }
        if firstHasPhoto != secondHasPhoto { return firstHasPhoto }
        return firstNoteCount >= secondNoteCount
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
    Dictionary([("same", 1), ("same", 2)], uniquingKeysWith: { first, _ in first })["same"] == 1,
    "Duplicate sync keys keep the first item instead of crashing"
)

let olderEdit = Date(timeIntervalSince1970: 10)
let newerEdit = Date(timeIntervalSince1970: 20)
expect(
    PartnerEditMerge.shouldApplyRemoteFields(
        myRole: .deena,
        localUpdated: olderEdit,
        remoteUpdated: newerEdit,
        localEditor: "deena",
        remoteEditor: "chris",
        contentChanged: true
    ),
    "Deena applies Chris's newer item edit"
)
expect(
    PartnerEditMerge.shouldApplyRemoteFields(
        myRole: .chris,
        localUpdated: olderEdit,
        remoteUpdated: newerEdit,
        localEditor: "chris",
        remoteEditor: "deena",
        contentChanged: true
    ),
    "Chris applies Deena's newer item edit"
)
expect(
    PartnerEditMerge.shouldApplyRemoteFields(
        myRole: .chris,
        localUpdated: olderEdit,
        remoteUpdated: PartnerEditMerge.timestamp(updatedAt: nil, modificationDate: newerEdit),
        localEditor: "chris",
        remoteEditor: "deena",
        contentChanged: true
    ),
    "Chris applies Deena's edit when only CloudKit modificationDate is present"
)
expect(
    PartnerEditMerge.shouldSkipCatchupPush(
        myRole: .deena,
        localUpdated: olderEdit,
        remoteUpdated: newerEdit,
        localEditor: "deena",
        remoteEditor: "chris",
        ownHeartMatches: true
    ),
    "Deena does not overwrite Chris's newer cloud edit on catchup"
)
expect(
    PartnerEditMerge.shouldSkipCatchupPush(
        myRole: .chris,
        localUpdated: olderEdit,
        remoteUpdated: newerEdit,
        localEditor: "chris",
        remoteEditor: "deena",
        ownHeartMatches: true
    ),
    "Chris does not overwrite Deena's newer cloud edit on catchup"
)
expect(
    PartnerEditMerge.shouldSkipCatchupPush(
        myRole: .chris,
        localUpdated: newerEdit,
        remoteUpdated: olderEdit,
        localEditor: "chris",
        remoteEditor: "deena",
        ownHeartMatches: true
    ) == false,
    "Chris still uploads when his local edit is newer"
)
expect(
    PartnerEditMerge.shouldApplyRemoteFields(
        myRole: .chris,
        localUpdated: newerEdit,
        remoteUpdated: olderEdit,
        localEditor: "chris",
        remoteEditor: "deena",
        contentChanged: true
    ) == false,
    "Chris keeps a newer local edit instead of rolling back to Deena"
)

if failed > 0 {
    fputs("\(failed) test(s) failed\n", stderr)
    exit(1)
}
print("All tests passed")
