import Foundation
import Observation
import SwiftData
import CloudKit
import UIKit
import UserNotifications

enum PairRole: String {
    case chris
    case deena
}

@Observable
@MainActor
final class PairSession {
    static let shared = PairSession()

    var pairID: String?
    var role: PairRole?
    var inviteCode: String?
    var myName = ""
    var partnerName = ""
    var statusMessage = ""
    var isBusy = false

    private let defaults = UserDefaults.standard
    private let pairKey = "todo42.pairID"
    private let roleKey = "todo42.pairRole"
    private let codeKey = "todo42.inviteCode"
    private let myNameKey = "todo42.myName"
    private let partnerNameKey = "todo42.partnerName"
    private let pairHistoryKey = "todo42.pairIDHistory"

    var isPaired: Bool { pairID != nil && role != nil }
    var isApplyingRemote = false

    var trimmedMyName: String {
        myName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedPartnerName: String {
        partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasNames: Bool {
        !trimmedMyName.isEmpty && !trimmedPartnerName.isEmpty
    }

    var myHeartLabel: String { trimmedMyName.isEmpty ? "Me" : trimmedMyName }
    var partnerHeartLabel: String { trimmedPartnerName.isEmpty ? "Partner" : trimmedPartnerName }
    var revealCategoryRaw: String?

    func takeRevealCategory() -> ItemCategory? {
        guard let raw = revealCategoryRaw else { return nil }
        revealCategoryRaw = nil
        return ItemCategory(rawValue: raw)
    }

    var hostName: String { role == .deena ? trimmedPartnerName : trimmedMyName }
    var guestName: String { role == .deena ? trimmedMyName : trimmedPartnerName }

    private init() {
        pairID = defaults.string(forKey: pairKey)
        if let raw = defaults.string(forKey: roleKey) {
            role = PairRole(rawValue: raw)
        }
        inviteCode = defaults.string(forKey: codeKey)
        myName = defaults.string(forKey: myNameKey) ?? ""
        partnerName = defaults.string(forKey: partnerNameKey) ?? ""
    }

    var rememberedPairIDs: [String] {
        defaults.stringArray(forKey: pairHistoryKey) ?? []
    }

    func unpair() {
        rememberPairID(pairID)
        pairID = nil
        role = nil
        inviteCode = nil
        statusMessage = ""
        persistLocal()
    }

    func persist() {
        persistLocal()
        if isPaired {
            Task { await CloudSync.shared.uploadPairNames() }
        }
    }

    func persistLocal() {
        rememberPairID(pairID)
        defaults.set(pairID, forKey: pairKey)
        defaults.set(role?.rawValue, forKey: roleKey)
        defaults.set(inviteCode, forKey: codeKey)
        defaults.set(myName, forKey: myNameKey)
        defaults.set(partnerName, forKey: partnerNameKey)
    }

    private func rememberPairID(_ id: String?) {
        guard let id, !id.isEmpty else { return }
        var history = defaults.stringArray(forKey: pairHistoryKey) ?? []
        history.removeAll { $0 == id }
        history.insert(id, at: 0)
        defaults.set(Array(history.prefix(20)), forKey: pairHistoryKey)
    }

    func applyRemoteNames(host: String?, guest: String?) {
        let hostName = host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let guestName = guest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if role == .deena {
            if !guestName.isEmpty { myName = guestName }
            if !hostName.isEmpty { partnerName = hostName }
        } else {
            if !hostName.isEmpty { myName = hostName }
            if !guestName.isEmpty { partnerName = guestName }
        }
        persistLocal()
    }

    func displayName(forEditor editor: String) -> String {
        if editor == PairRole.chris.rawValue {
            return hostName.isEmpty ? "Partner" : hostName
        }
        if editor == PairRole.deena.rawValue {
            return guestName.isEmpty ? "Partner" : guestName
        }
        return editor.capitalized
    }

    func noteLocalEdit(_ item: TodoItem, kind: String) {
        guard !isApplyingRemote else { return }
        item.updatedAt = Date()
        item.lastEditor = role?.rawValue ?? ""
        Task { await CloudSync.shared.upload(item, notifyKind: kind) }
    }
}

@MainActor
final class CloudSync {
    static let shared = CloudSync()
    static let containerID = "iCloud.com.chrisfleck.ToDo42"

    private init() {}

    private var container: CKContainer { CKContainer(identifier: Self.containerID) }
    private var database: CKDatabase { container.publicCloudDatabase }

    private var operationTail: Task<Void, Never> = Task {}

    private func enqueue(_ work: @escaping () async -> Void) async {
        let previous = operationTail
        let current = Task {
            await previous.value
            await work()
        }
        operationTail = current
        await current.value
    }

    private static func friendlyMessage(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                return "Couldn't reach iCloud. Try again in a moment."
            case .notAuthenticated:
                return "Sign in to iCloud on this iPhone so the lists can sync."
            case .quotaExceeded:
                return "iCloud storage is full on this Apple Account."
            default:
                break
            }
        }
        return "Couldn't sync the list. Try again in a moment."
    }

    private func saveOverwriting(_ record: CKRecord) async throws {
        let outcome = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .allKeys
        )
        if let result = outcome.saveResults[record.recordID] {
            switch result {
            case .success:
                break
            case .failure(let error):
                throw error
            }
        }
    }

    func createInvite() async throws -> String {
        try await ensureiCloud()
        let pairID = UUID().uuidString
        let code = String((0..<6).map { _ in "0123456789".randomElement()! })

        let codeRecord = CKRecord(recordType: "TDPairCode", recordID: CKRecord.ID(recordName: "code-\(code)"))
        codeRecord["pairID"] = pairID
        codeRecord["createdAt"] = Date()

        let pairRecord = CKRecord(recordType: "TDPair", recordID: CKRecord.ID(recordName: "pair-\(pairID)"))
        pairRecord["itemIDs"] = ""
        pairRecord["createdAt"] = Date()
        pairRecord["hostName"] = PairSession.shared.trimmedMyName
        pairRecord["guestName"] = PairSession.shared.trimmedPartnerName

        _ = try await database.modifyRecords(saving: [codeRecord, pairRecord], deleting: [], savePolicy: .allKeys)

        let session = PairSession.shared
        session.pairID = pairID
        session.role = .chris
        session.inviteCode = code
        session.persistLocal()
        try await subscribe()
        try await requestNotifications()
        return code
    }

    func join(code: String) async throws {
        try await ensureiCloud()
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6 else { throw SyncError.message("Enter the 6-digit code.") }
        let record: CKRecord
        do {
            record = try await database.record(for: CKRecord.ID(recordName: "code-\(trimmed)"))
        } catch {
            if let ck = error as? CKError, ck.code == .unknownItem {
                throw SyncError.message("That code was not found. Chris must tap “New invite code” in the TestFlight app (not the copy installed from Xcode), then send you the new 6-digit code.")
            }
            throw SyncError.message(Self.friendlyMessage(error))
        }
        guard let pairID = record["pairID"] as? String, !pairID.isEmpty else {
            throw SyncError.message("That code was not found.")
        }
        let session = PairSession.shared
        session.pairID = pairID
        session.role = .deena
        session.inviteCode = trimmed
        session.persistLocal()
        if let pair = try? await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)")) {
            let host = pair["hostName"] as? String ?? ""
            if !host.isEmpty {
                session.partnerName = host
            }
            pair["guestName"] = session.trimmedMyName
            if session.trimmedPartnerName.isEmpty == false, host.isEmpty {
                pair["hostName"] = session.trimmedPartnerName
            }
            try await saveOverwriting(pair)
        }
        session.persistLocal()
        try await subscribe()
        try await requestNotifications()
    }

    func uploadPairNames() async {
        guard PairSession.shared.isPaired, let pairID = PairSession.shared.pairID else { return }
        await enqueue {
            do {
                let record = try await self.database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
                record["hostName"] = PairSession.shared.hostName
                record["guestName"] = PairSession.shared.guestName
                try await self.saveOverwriting(record)
            } catch {
                PairSession.shared.statusMessage = Self.friendlyMessage(error)
            }
        }
    }

    func sync(modelContext: ModelContext, allowCreate: Bool = false) async {
        guard PairSession.shared.isPaired else { return }
        await enqueue {
            do {
                try await self.ensureiCloud()
                ItemStore.deduplicate(in: modelContext)
                if allowCreate {
                    try await self.pushAll(ItemStore.allItems(in: modelContext), allowCreate: true)
                    try await self.pull(modelContext: modelContext)
                } else {
                    try await self.pull(modelContext: modelContext)
                    try await self.pushAll(ItemStore.allItems(in: modelContext), allowCreate: false)
                }
                PairSession.shared.statusMessage = ""
            } catch {
                PairSession.shared.statusMessage = Self.friendlyMessage(error)
            }
        }
    }

    func upload(_ item: TodoItem, notifyKind: String) async {
        guard PairSession.shared.isPaired else { return }
        await enqueue {
            do {
                try await self.saveItem(item, notifyKind: notifyKind)
                try? await self.registerItemIDs([item.id.uuidString])
                PairSession.shared.statusMessage = ""
            } catch {
                PairSession.shared.statusMessage = Self.friendlyMessage(error)
            }
        }
    }

    func restoreFromCloud(modelContext: ModelContext, oldCode: String = "") async {
        await enqueue {
            do {
                try await self.ensureiCloud()
                let result = await self.fetchRecoverableItemRecords(oldCode: oldCode)
                let records = result.records
                let session = PairSession.shared
                session.isApplyingRemote = true
                defer { session.isApplyingRemote = false }

                var localByID = ItemStore.keyedByID(ItemStore.allItems(in: modelContext))
                let itemRecords = records.filter { !$0.recordID.recordName.hasPrefix("extra-") }
                let extraRecords = records.filter { $0.recordID.recordName.hasPrefix("extra-") }
                for record in itemRecords {
                    guard let itemID = record["itemID"] as? String, let uuid = UUID(uuidString: itemID) else { continue }
                    if let local = localByID[itemID] {
                        self.apply(record, to: local)
                        continue
                    }
                    let item = TodoItem(
                        title: record["title"] as? String ?? "Untitled",
                        category: ItemCategory(rawValue: record["categoryRaw"] as? String ?? "places") ?? .places,
                        urlString: record["urlString"] as? String,
                        notes: record["notes"] as? String ?? "",
                        sortOrder: CloudKitValues.intValue(record["sortOrder"]) ?? 0
                    )
                    item.id = uuid
                    self.apply(record, to: item)
                    modelContext.insert(item)
                    localByID[itemID] = item
                }
                for record in extraRecords {
                    let itemID = record["itemID"] as? String
                        ?? String(record.recordID.recordName.dropFirst("extra-".count))
                    if let local = localByID[itemID] {
                        self.applyExtraPhoto(record, to: local)
                    }
                }
                try? modelContext.save()
                if session.isPaired {
                    try await self.pushAll(ItemStore.allItems(in: modelContext), allowCreate: true)
                }
                let total = ItemStore.allItems(in: modelContext).count
                if records.isEmpty {
                    session.statusMessage = result.emptyMessage
                } else {
                    session.statusMessage = "Restored \(total) item\(total == 1 ? "" : "s") from iCloud."
                }
            } catch {
                PairSession.shared.statusMessage = Self.friendlyMessage(error)
            }
        }
    }

    func deleteRemote(_ id: UUID) async {
        guard PairSession.shared.isPaired else { return }
        await enqueue {
            do {
                try await self.database.deleteRecord(withID: CKRecord.ID(recordName: "item-\(id.uuidString)"))
                try? await self.database.deleteRecord(withID: self.extraRecordID(for: id))
                try await self.removeItemID(id.uuidString)
                PairSession.shared.statusMessage = ""
            } catch {
                PairSession.shared.statusMessage = Self.friendlyMessage(error)
            }
        }
    }

    func handleRemoteNotification(modelContext: ModelContext) async {
        await sync(modelContext: modelContext)
    }

    func inviteText(code: String) -> String {
        """
        Join \(PairSession.shared.trimmedMyName.isEmpty ? "me" : PairSession.shared.trimmedMyName) on Save4Two.

        1. Both of us install Save4Two from TestFlight (not from Xcode).
        2. Open the app and tap the two-person icon.
        3. Choose “I have a code” and enter: \(code)

        Stay signed in to iCloud on your iPhone so our lists can sync.
        """
    }

    private func pull(modelContext: ModelContext) async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        let pair = try await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
        PairSession.shared.applyRemoteNames(
            host: pair["hostName"] as? String,
            guest: pair["guestName"] as? String
        )
        let listedIDs = (pair["itemIDs"] as? String ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
        let fetched = await fetchRemoteItemRecords(pairID: pairID, listedIDs: listedIDs)
        let remote = fetched.records.filter { !$0.recordID.recordName.hasPrefix("extra-") }
        let extraRecords = fetched.records.filter { $0.recordID.recordName.hasPrefix("extra-") }

        let session = PairSession.shared
        session.isApplyingRemote = true
        defer { session.isApplyingRemote = false }

        var localByID = ItemStore.keyedByID(ItemStore.allItems(in: modelContext))
        for record in remote {
            guard let itemID = record["itemID"] as? String, let uuid = UUID(uuidString: itemID) else { continue }
            let remoteUpdated = record["updatedAt"] as? Date ?? .distantPast
            let local = localByID[itemID] ?? ItemStore.item(id: uuid, in: modelContext)
            if let local {
                let remoteChris = CloudKitValues.flag(record["chrisHearted"])
                let remoteDeena = CloudKitValues.flag(record["deenaHearted"])
                let justHearted = PartnerHeartMerge.partnerJustHearted(
                    myRole: session.role,
                    localChris: local.chrisHearted,
                    localDeena: local.deenaHearted,
                    remoteChris: remoteChris,
                    remoteDeena: remoteDeena
                )
                local.chrisHearted = PartnerHeartMerge.mergedChris(
                    myRole: session.role,
                    localChris: local.chrisHearted,
                    remoteChris: remoteChris
                )
                local.deenaHearted = PartnerHeartMerge.mergedDeena(
                    myRole: session.role,
                    localDeena: local.deenaHearted,
                    remoteDeena: remoteDeena
                )
                if remoteUpdated > (local.updatedAt ?? local.createdAt) {
                    apply(record, to: local, hearts: false)
                    notifyUpdate(record, heartChanged: justHearted)
                } else if justHearted {
                    notifyUpdate(record, heartChanged: true)
                }
            } else {
                let item = TodoItem(
                    title: record["title"] as? String ?? "Untitled",
                    category: ItemCategory(rawValue: record["categoryRaw"] as? String ?? "places") ?? .places,
                    urlString: record["urlString"] as? String,
                    notes: record["notes"] as? String ?? "",
                    sortOrder: CloudKitValues.intValue(record["sortOrder"]) ?? 0
                )
                item.id = uuid
                apply(record, to: item)
                modelContext.insert(item)
                localByID[itemID] = item
                if (record["lastEditor"] as? String ?? "") != (session.role?.rawValue ?? "") {
                    session.revealCategoryRaw = item.categoryRaw
                }
                notifyNew(record)
            }
        }
        for record in extraRecords {
            let itemID = record["itemID"] as? String
                ?? String(record.recordID.recordName.dropFirst("extra-".count))
            guard let local = localByID[itemID] ?? {
                guard let uuid = UUID(uuidString: itemID) else { return nil }
                return ItemStore.item(id: uuid, in: modelContext)
            }() else { continue }
            applyExtraPhoto(record, to: local)
        }
        if fetched.catalogComplete, !remote.isEmpty {
            let remoteIDs = Set(remote.compactMap { $0["itemID"] as? String })
            let extrasByItemID = Set(extraRecords.compactMap { record -> String? in
                if let itemID = record["itemID"] as? String, !itemID.isEmpty { return itemID }
                return String(record.recordID.recordName.dropFirst("extra-".count))
            })
            for local in ItemStore.allItems(in: modelContext) {
                if remoteIDs.contains(local.id.uuidString) {
                    if local.hasExtraPhoto, !extrasByItemID.contains(local.id.uuidString) {
                        let remoteItem = remote.first {
                            ($0["itemID"] as? String) == local.id.uuidString
                        }
                        let remoteUpdated = remoteItem?["updatedAt"] as? Date
                            ?? remoteItem?.modificationDate
                            ?? .distantPast
                        if remoteUpdated >= (local.updatedAt ?? local.createdAt) {
                            local.extraImageData = nil
                        }
                    }
                    continue
                }
                if Date().timeIntervalSince(local.createdAt) < 180 { continue }
                modelContext.delete(local)
            }
        }
        try? modelContext.save()
    }

    private func pushAll(_ items: [TodoItem], allowCreate: Bool) async throws {
        for item in items {
            try await saveItem(item, notifyKind: "", allowCreate: allowCreate)
        }
        try? await registerItemIDs(items.map(\.id.uuidString))
    }

    private func fetchRemoteItemRecords(pairID: String, listedIDs: [String]) async -> (records: [CKRecord], catalogComplete: Bool) {
        var found: [String: CKRecord] = [:]
        var catalogComplete = false

        let pairQuery = CKQuery(
            recordType: "TDItem",
            predicate: NSPredicate(format: "pairID == %@", pairID)
        )
        if let queried = try? await queryAll(pairQuery) {
            catalogComplete = true
            for record in queried {
                found[record.recordID.recordName] = record
            }
        }

        if !catalogComplete {
            let anyQuery = CKQuery(recordType: "TDItem", predicate: NSPredicate(value: true))
            if let queried = try? await queryAll(anyQuery) {
                catalogComplete = true
                for record in queried where (record["pairID"] as? String) == pairID {
                    found[record.recordID.recordName] = record
                }
            }
        }

        let missing = listedIDs.filter { found["item-\($0)"] == nil }
        if !missing.isEmpty {
            for record in await fetchNamedRecords(missing.map { "item-\($0)" }) {
                found[record.recordID.recordName] = record
            }
        }
        let missingExtras = listedIDs.filter { found["extra-\($0)"] == nil }
        if !missingExtras.isEmpty {
            for record in await fetchNamedRecords(missingExtras.map { "extra-\($0)" }) {
                found[record.recordID.recordName] = record
            }
        }
        return (Array(found.values), catalogComplete)
    }

    private func fetchRecoverableItemRecords(oldCode: String) async -> (records: [CKRecord], emptyMessage: String) {
        var found: [String: CKRecord] = [:]
        var lastError: String?

        func add(_ records: [CKRecord]) {
            for record in records {
                found[record.recordID.recordName] = record
            }
        }

        func queryItems(_ predicate: NSPredicate) async {
            do {
                add(try await queryAll(CKQuery(recordType: "TDItem", predicate: predicate)))
            } catch {
                lastError = Self.friendlyMessage(error)
            }
        }

        func addItems(forPair pairID: String) async {
            await queryItems(NSPredicate(format: "pairID == %@", pairID))
            if let pair = try? await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)")) {
                let ids = (pair["itemIDs"] as? String ?? "")
                    .split(separator: ",")
                    .map(String.init)
                    .filter { !$0.isEmpty }
                add(await fetchNamedRecords(ids.map { "item-\($0)" }))
            }
        }

        let session = PairSession.shared
        var pairIDs = Set(session.rememberedPairIDs)
        if let current = session.pairID { pairIDs.insert(current) }

        let trimmedCode = oldCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCode.count == 6 {
            do {
                let codeRecord = try await database.record(for: CKRecord.ID(recordName: "code-\(trimmedCode)"))
                if let pairID = codeRecord["pairID"] as? String, !pairID.isEmpty {
                    pairIDs.insert(pairID)
                }
            } catch {
                if found.isEmpty {
                    return ([], "That older code was not found in iCloud. Check Messages for a previous 6-digit code.")
                }
            }
        }

        let names = [session.trimmedMyName, session.trimmedPartnerName].filter { !$0.isEmpty }
        for name in names {
            for key in ["hostName", "guestName"] {
                do {
                    let pairs = try await queryAll(
                        CKQuery(recordType: "TDPair", predicate: NSPredicate(format: "%K == %@", key, name))
                    )
                    for pair in pairs {
                        let pairID = pair.recordID.recordName.replacingOccurrences(of: "pair-", with: "")
                        if !pairID.isEmpty { pairIDs.insert(pairID) }
                    }
                } catch {
                    lastError = Self.friendlyMessage(error)
                }
            }
        }

        for pairID in pairIDs {
            await addItems(forPair: pairID)
        }

        for category in ItemCategory.allCases {
            await queryItems(NSPredicate(format: "categoryRaw == %@", category.rawValue))
        }
        for editor in ["chris", "deena"] {
            await queryItems(NSPredicate(format: "lastEditor == %@", editor))
        }

        if found.isEmpty {
            do {
                add(try await queryAll(CKQuery(recordType: "TDItem", predicate: NSPredicate(value: true))))
            } catch {
                lastError = Self.friendlyMessage(error)
            }
        }

        if found.isEmpty {
            let hint = "Enter an older 6-digit invite code from Messages, then tap Restore again."
            if let lastError {
                return ([], "iCloud search failed. \(lastError) \(hint)")
            }
            return ([], "Could not find the old list in iCloud. \(hint)")
        }
        return (Array(found.values), "")
    }

    private func queryAll(_ query: CKQuery) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let matchResults: [(CKRecord.ID, Result<CKRecord, Error>)]
            let next: CKQueryOperation.Cursor?
            if let cursor {
                (matchResults, next) = try await database.records(continuingMatchFrom: cursor)
            } else {
                (matchResults, next) = try await database.records(matching: query, inZoneWith: nil)
            }
            for (_, result) in matchResults {
                if let record = try? result.get() {
                    records.append(record)
                }
            }
            cursor = next
        } while cursor != nil
        return records
    }

    private func fetchNamedRecords(_ names: [String]) async -> [CKRecord] {
        var records: [CKRecord] = []
        let ids = names.map { CKRecord.ID(recordName: $0) }
        var start = 0
        while start < ids.count {
            let end = min(start + 100, ids.count)
            let batch = Array(ids[start..<end])
            if let result = try? await database.records(for: batch) {
                for id in batch {
                    if let record = try? result[id]?.get() {
                        records.append(record)
                    }
                }
            }
            start = end
        }
        return records
    }

    private func saveItem(_ item: TodoItem, notifyKind: String, allowCreate: Bool = true) async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        let recordID = CKRecord.ID(recordName: "item-\(item.id.uuidString)")
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            if notifyKind.isEmpty, shouldSkipCatchupPush(item, existing: existing) {
                // Still publish a local bottom photo that never made it to iCloud
                // (older builds dropped those uploads), without rewriting newer fields.
                if item.hasExtraPhoto {
                    try await saveExtraPhotoRecord(for: item, pairID: pairID)
                }
                return
            }
            record = existing
        } else {
            guard allowCreate || !notifyKind.isEmpty else { return }
            record = CKRecord(recordType: "TDItem", recordID: recordID)
            record["chrisHearted"] = item.chrisHearted ? 1 : 0
            record["deenaHearted"] = item.deenaHearted ? 1 : 0
        }
        record["itemID"] = item.id.uuidString
        record["pairID"] = pairID
        record["title"] = item.title
        record["urlString"] = item.urlString ?? ""
        record["notes"] = item.notes
        record["categoryRaw"] = item.categoryRaw
        switch PairSession.shared.role {
        case .chris:
            record["chrisHearted"] = item.chrisHearted ? 1 : 0
        case .deena:
            record["deenaHearted"] = item.deenaHearted ? 1 : 0
        case nil:
            record["chrisHearted"] = item.chrisHearted ? 1 : 0
            record["deenaHearted"] = item.deenaHearted ? 1 : 0
        }
        record["isDone"] = item.isDone ? 1 : 0
        record["sortOrder"] = item.sortOrder
        record["createdAt"] = item.createdAt
        record["updatedAt"] = item.updatedAt ?? item.createdAt
        record["lastEditor"] = item.lastEditor
        if !notifyKind.isEmpty {
            record["notifyKind"] = notifyKind
        }
        if let data = item.imageData, !data.isEmpty {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id.uuidString).jpg")
            try data.write(to: url)
            record["image"] = CKAsset(fileURL: url)
        }
        try await saveOverwriting(record)
        // Bottom photos use a companion record with the existing `image` asset field.
        // Writing a second `image2` field on the item used to happen in a follow-up
        // save that failed silently on Production CloudKit, so partners never saw it.
        try await saveExtraPhotoRecord(for: item, pairID: pairID)
    }

    /// Bottom-of-page photos sync through a companion TDItem that reuses the known
    /// `image` asset field, so Production CloudKit does not need a new `image2` field.
    private func extraRecordID(for itemID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "extra-\(itemID.uuidString)")
    }

    private func saveExtraPhotoRecord(for item: TodoItem, pairID: String) async throws {
        let recordID = extraRecordID(for: item.id)
        guard let extra = item.extraImageData, !extra.isEmpty else {
            try? await database.deleteRecord(withID: recordID)
            return
        }
        let record = (try? await database.record(for: recordID))
            ?? CKRecord(recordType: "TDItem", recordID: recordID)
        record["pairID"] = pairID
        record["itemID"] = item.id.uuidString
        record["title"] = ""
        record["urlString"] = ""
        record["notes"] = ""
        record["categoryRaw"] = item.categoryRaw
        record["chrisHearted"] = 0
        record["deenaHearted"] = 0
        record["isDone"] = 0
        record["sortOrder"] = -1
        record["createdAt"] = item.createdAt
        record["updatedAt"] = item.updatedAt ?? item.createdAt
        record["lastEditor"] = item.lastEditor
        let extraURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id.uuidString)-extra.jpg")
        try extra.write(to: extraURL)
        record["image"] = CKAsset(fileURL: extraURL)
        try await saveOverwriting(record)
    }

    private func applyExtraPhoto(_ record: CKRecord, to item: TodoItem) {
        let remoteUpdated = record["updatedAt"] as? Date ?? record.modificationDate ?? .distantPast
        if item.hasExtraPhoto, (item.updatedAt ?? item.createdAt) > remoteUpdated {
            return
        }
        if let asset = record["image"] as? CKAsset, let url = asset.fileURL,
           let data = try? Data(contentsOf: url), !data.isEmpty, data.count < 8_000_000 {
            item.extraImageData = data
            if (item.updatedAt ?? .distantPast) < remoteUpdated {
                item.updatedAt = remoteUpdated
            }
            if let editor = record["lastEditor"] as? String, !editor.isEmpty {
                item.lastEditor = editor
            }
        }
    }

    private func apply(_ record: CKRecord, to item: TodoItem, hearts: Bool = true) {
        item.title = record["title"] as? String ?? item.title
        let url = record["urlString"] as? String ?? ""
        item.urlString = url.isEmpty ? nil : url
        item.notes = record["notes"] as? String ?? item.notes
        item.categoryRaw = record["categoryRaw"] as? String ?? item.categoryRaw
        if hearts {
            item.chrisHearted = CloudKitValues.flag(record["chrisHearted"])
            item.deenaHearted = CloudKitValues.flag(record["deenaHearted"])
        }
        item.isDone = CloudKitValues.flag(record["isDone"])
        item.sortOrder = CloudKitValues.intValue(record["sortOrder"]) ?? item.sortOrder
        item.createdAt = record["createdAt"] as? Date ?? item.createdAt
        item.updatedAt = record["updatedAt"] as? Date ?? item.updatedAt
        item.lastEditor = record["lastEditor"] as? String ?? item.lastEditor
        if let asset = record["image"] as? CKAsset, let url = asset.fileURL,
           let data = try? Data(contentsOf: url), data.count < 8_000_000 {
            item.imageData = data
        }
        if let asset = record["image2"] as? CKAsset, let url = asset.fileURL,
           let data = try? Data(contentsOf: url), data.count < 8_000_000 {
            item.extraImageData = data
        }
    }

    private func shouldSkipCatchupPush(_ item: TodoItem, existing: CKRecord) -> Bool {
        let remoteUpdated = existing["updatedAt"] as? Date ?? .distantPast
        let localUpdated = item.updatedAt ?? item.createdAt
        guard remoteUpdated >= localUpdated else { return false }
        switch PairSession.shared.role {
        case .chris:
            return CloudKitValues.flag(existing["chrisHearted"]) == item.chrisHearted
        case .deena:
            return CloudKitValues.flag(existing["deenaHearted"]) == item.deenaHearted
        case nil:
            return true
        }
    }

    private func registerItemIDs(_ itemIDs: [String]) async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        guard !itemIDs.isEmpty else { return }
        let record = try await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
        var ids = Set((record["itemIDs"] as? String ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty })
        let before = ids.count
        itemIDs.forEach { ids.insert($0) }
        guard ids.count != before else { return }
        record["itemIDs"] = ids.sorted().joined(separator: ",")
        do {
            try await saveOverwriting(record)
        } catch {
            // The ID list can be too long for iCloud; items still sync by pairID.
        }
    }

    private func removeItemID(_ itemID: String) async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        let record = try await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
        let ids = (record["itemIDs"] as? String ?? "").split(separator: ",").map(String.init).filter { $0 != itemID && !$0.isEmpty }
        record["itemIDs"] = ids.joined(separator: ",")
        try await saveOverwriting(record)
    }

    private func subscribe() async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.shouldBadge = false

        let subscription = CKQuerySubscription(
            recordType: "TDItem",
            predicate: NSPredicate(format: "pairID == %@", pairID),
            subscriptionID: "todo42-tditem-\(pairID.prefix(8))",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        subscription.notificationInfo = info
        do {
            _ = try await database.save(subscription)
        } catch {
            let fallback = CKQuerySubscription(
                recordType: "TDItem",
                predicate: NSPredicate(value: true),
                subscriptionID: "todo42-tditem-all",
                options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
            )
            fallback.notificationInfo = info
            _ = try? await database.save(fallback)
        }
    }

    private func requestNotifications() async throws {
        let center = UNUserNotificationCenter.current()
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func ensureiCloud() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw SyncError.message("Sign in to iCloud on this iPhone (Settings → Apple Account → iCloud) so the lists can sync.")
        }
    }

    private func notifyNew(_ record: CKRecord) {
        let editor = record["lastEditor"] as? String ?? ""
        guard editor != PairSession.shared.role?.rawValue else { return }
        let who = PairSession.shared.displayName(forEditor: editor)
        let title = record["title"] as? String ?? "an item"
        postNotice(title: "\(who) added an item", body: title)
    }

    private func notifyUpdate(_ record: CKRecord, heartChanged: Bool) {
        let title = record["title"] as? String ?? "an item"
        if heartChanged {
            let who = PairSession.shared.partnerHeartLabel
            postNotice(title: "\(who) hearted an item", body: title)
            return
        }
        let editor = record["lastEditor"] as? String ?? ""
        guard editor != PairSession.shared.role?.rawValue else { return }
        let who = PairSession.shared.displayName(forEditor: editor)
        postNotice(title: "\(who) updated an item", body: title)
    }

    private func postNotice(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum SyncError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}
