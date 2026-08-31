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

    static func date(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let number = value as? NSNumber {
            let interval = number.doubleValue
            if interval > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: interval / 1000)
            }
            if interval > 1_000_000_000 {
                return Date(timeIntervalSince1970: interval)
            }
        }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let interval = Double(trimmed) {
                return Date(timeIntervalSince1970: interval)
            }
            return ISO8601DateFormatter().date(from: trimmed)
        }
        return nil
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

    static func contentChanged(
        localTitle: String,
        remoteTitle: String,
        localNotes: String,
        remoteNotes: String,
        localURL: String,
        remoteURL: String,
        localCategory: String,
        remoteCategory: String,
        localDone: Bool,
        remoteDone: Bool,
        localSort: Int,
        remoteSort: Int
    ) -> Bool {
        localTitle != remoteTitle
            || localNotes != remoteNotes
            || localURL != remoteURL
            || localCategory != remoteCategory
            || localDone != remoteDone
            || localSort != remoteSort
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
        secondUpdated: Date,
        secondHasPhoto: Bool,
        secondNoteCount: Int
    ) -> Bool {
        if firstUpdated != secondUpdated { return firstUpdated > secondUpdated }
        if firstHasPhoto != secondHasPhoto { return firstHasPhoto }
        return firstNoteCount >= secondNoteCount
    }
}
