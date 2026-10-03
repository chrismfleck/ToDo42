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

    /// Prefix stored in the existing `itemIDs` field. Production CloudKit rejects
    /// a brand-new `deletedIDs` field, so a delete has to live in a field both
    /// phones can already write. `x:<uuid>` is not a list row.
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

    /// Drop these ids from the live catalog and remember them with an `x:` mark.
    /// Marks stay in insertion order so the cap keeps the most recent deletes.
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

    /// Merge item-id catalogs from two devices without losing either side's
    /// additions (used when reconciling the pair record's `itemIDs` string).
    /// Ids already marked deleted are not added back.
    static func mergedItemIDs(_ a: String?, _ b: [String]) -> String {
        let deleted = Set(deletedIDs(in: a))
        var ids = Set(liveItemIDs(in: a))
        for id in b where !id.isEmpty && !deleted.contains(id) && markedDeletedID(id) == nil {
            ids.insert(id)
        }
        let marks = deletedIDs(in: a).map { deletedMark + $0 }
        return (ids.sorted() + marks).joined(separator: ",")
    }

    /// Stable key so the same YouTube video counts as one item across
    /// `youtu.be` and `youtube.com/watch` links. Other links compare as text.
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

    /// Append ids to the pair's `deletedIDs` list (a co-writable tombstone list
    /// on the pair record). Insertion order is preserved so the cap keeps the
    /// most recently deleted ids; both devices can write this even when they do
    /// not own the item's own CloudKit row (public DB records are creator-only).
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

    /// Remove one id from a catalog string while preserving every other id
    /// (so a concurrent add on the other device is not clobbered).
    static func removingItemID(_ catalog: String?, _ itemID: String) -> String {
        (catalog ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { $0 != itemID && !$0.isEmpty }
            .sorted()
            .joined(separator: ",")
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

    /// Catch-up pushes (`allowCreate: false`, empty `notifyKind`) must not invent
    /// CloudKit rows that are simply missing — that resurrected hard-deleted items
    /// when the partner still held a local copy. Explicit adds/edits and full
    /// restore (`allowCreate: true`) still create records as before.
    static func shouldCreateMissingRecord(allowCreate: Bool, notifyKind: String, title: String) -> Bool {
        if allowCreate { return true }
        let kind = notifyKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !kind.isEmpty, kind != "delete" else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || kind == "heart"
            || kind == "reorder"
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

    /// A re-push (catch-up `pushAll` or an edit) must never overwrite a
    /// tombstoned record, or a delete on one device gets resurrected by the
    /// other device that still holds the item locally. Delete wins.
    static func shouldSkipSaveOverTombstone(existingNotifyKind: String?) -> Bool {
        isTombstone(notifyKind: existingNotifyKind)
    }

    /// True when a row/item was last touched by us (or has no editor yet). Used
    /// to tell an own add whose catalog registration merely raced/failed (heal
    /// it) apart from a genuine remote removal (which arrives as a tombstone).
    static func isOwnEdit(lastEditor: String?, myRole: String?) -> Bool {
        let editor = (lastEditor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if editor.isEmpty { return true }
        return editor == (myRole ?? "")
    }

    /// A live CloudKit row missing from the shared catalog is usually a brand-new
    /// add whose `registerItemIDs` raced behind the TDItem push that wakes the
    /// partner. Accept `notifyKind == "add"` or a recently created row so the
    /// partner inserts it; older uncatalogued rows stay ignored (pre-tombstone
    /// hard-deletes). Authoritative deletes must already have been filtered via
    /// `deletedIDs` / `x:` marks / the local ledger before this is consulted.
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

/// Deletes this phone has made. Survives relaunch, and is checked before any
/// iCloud row is shown again. A partner still on an older build can push a
/// YouTube item back into the catalog; this list is what keeps it off the screen.
enum DeletedItemLedger {
    private struct Record: Codable {
        var id: String
        var urlKey: String
    }

    private static let cap = 500
    private static let keyPrefix = "todo42.deletedLedger.v1."

    static func record(pairID: String?, id: UUID, urlString: String?) {
        let idString = id.uuidString
        var rows = load(pairID: pairID).filter { $0.id != idString }
        rows.append(Record(id: idString, urlKey: CloudKitValues.deletionURLKey(urlString) ?? ""))
        save(rows, pairID: pairID)
    }

    /// A deliberate new save of the same link should stick. The old row's id
    /// stays suppressed so that CloudKit copy cannot come back under the old id.
    static func allowAgain(pairID: String?, urlString: String?, id: UUID) {
        let idString = id.uuidString
        let key = CloudKitValues.deletionURLKey(urlString) ?? ""
        var rows = load(pairID: pairID).filter { $0.id != idString }
        if !key.isEmpty {
            for index in rows.indices where rows[index].urlKey == key {
                rows[index].urlKey = ""
            }
        }
        save(rows, pairID: pairID)
    }

    static func contains(pairID: String?, id: String) -> Bool {
        load(pairID: pairID).contains { $0.id == id }
    }

    static func containsURL(pairID: String?, urlString: String?) -> Bool {
        guard let key = CloudKitValues.deletionURLKey(urlString), !key.isEmpty else { return false }
        return load(pairID: pairID).contains { $0.urlKey == key }
    }

    static func ids(pairID: String?) -> [String] {
        load(pairID: pairID).map(\.id)
    }

    private static func storageKey(pairID: String?) -> String {
        let id = (pairID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return keyPrefix + (id.isEmpty ? "local" : id)
    }

    private static func load(pairID: String?) -> [Record] {
        guard let data = UserDefaults.standard.data(forKey: storageKey(pairID: pairID)),
              let rows = try? JSONDecoder().decode([Record].self, from: data) else {
            return []
        }
        return rows
    }

    private static func save(_ rows: [Record], pairID: String?) {
        let trimmed = rows.count > cap ? Array(rows.suffix(cap)) : rows
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(pairID: pairID))
    }
}
