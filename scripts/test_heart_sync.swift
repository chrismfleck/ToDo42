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

if failed > 0 {
    fputs("\(failed) test(s) failed\n", stderr)
    exit(1)
}
print("All tests passed")
