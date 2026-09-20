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
        if recordName.hasPrefix("extra3-") || recordName.hasPrefix("extra2-") || recordName.hasPrefix("extra-") {
            return .extraPhoto
        }
        if recordName.hasPrefix("item-") { return .listItem }
        // Negative sortOrder is reserved for companion photo rows, even if a
        // leftover title was written onto the CloudKit record.
        if let sortOrder, sortOrder < 0 { return .extraPhoto }
        let emptyTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        // Wiped extra-photo rows must never win, even if iCloud stamped them later.
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
        if recordName.hasPrefix("extra3-") {
            return String(recordName.dropFirst("extra3-".count))
        }
        if recordName.hasPrefix("extra2-") {
            return String(recordName.dropFirst("extra2-".count))
        }
        if recordName.hasPrefix("extra-") {
            return String(recordName.dropFirst("extra-".count))
        }
        return nil
    }

    static func extraSlot(recordName: String) -> Int? {
        if recordName.hasPrefix("extra3-") { return 3 }
        if recordName.hasPrefix("extra2-") { return 2 }
        if recordName.hasPrefix("extra-") { return 1 }
        return nil
    }

    static func isSecondExtraPhoto(recordName: String) -> Bool {
        extraSlot(recordName: recordName) == 2
    }

    static func isTombstone(notifyKind: String?) -> Bool {
        (notifyKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "delete"
    }

    static func shouldApplyRemoteSort(
        myRole: String?,
        lastEditor: String?,
        notifyKind: String?,
        localSort: Int,
        remoteSort: Int?,
        localUpdated: Date,
        remoteUpdated: Date
    ) -> Bool {
        guard let remoteSort, remoteSort != localSort else { return false }
        if lastEditor == myRole { return false }
        if notifyKind == "reorder" { return true }
        return remoteUpdated >= localUpdated
    }
}

enum ListReorder {
    static let spacing = 1000

    static func slot(prev: Int?, next: Int?) -> Int? {
        switch (prev, next) {
        case (nil, nil):
            return 0
        case (nil, let next?):
            return next - spacing
        case (let prev?, nil):
            return prev + spacing
        case (let prev?, let next?):
            guard next > prev + 1 else { return nil }
            return prev + (next - prev) / 2
        }
    }

    static func rebalanced(_ count: Int) -> [Int] {
        (0..<count).map { $0 * spacing }
    }
}
