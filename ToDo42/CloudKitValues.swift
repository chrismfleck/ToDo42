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
