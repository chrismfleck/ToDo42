import Foundation

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

    static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        if let int64 = value as? Int64 { return Int(int64) }
        if let text = value as? String {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
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

/// Companion bottom-photo records are also `TDItem` rows that reuse `image`.
/// They must never be applied as list items or they wipe titles and replace
/// the primary photo.
enum TDItemRecordKind: Equatable {
    case listItem
    case extraPhoto
    case unknown

    static func classify(recordName: String, title: String?, sortOrder: Int?) -> TDItemRecordKind {
        if recordName.hasPrefix("extra-") { return .extraPhoto }
        let emptyTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if sortOrder == -1, emptyTitle { return .extraPhoto }
        if recordName.hasPrefix("item-") { return .listItem }
        if emptyTitle { return .extraPhoto }
        return .unknown
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
        if remoteUpdated > localUpdated { return true }
        let localEmpty = localTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let remoteHasTitle = !(remoteTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return localEmpty && remoteHasTitle
    }

    static func extraItemID(recordName: String, itemID: String?) -> String? {
        if let itemID, !itemID.isEmpty { return itemID }
        if recordName.hasPrefix("extra-") {
            return String(recordName.dropFirst("extra-".count))
        }
        return nil
    }
}
