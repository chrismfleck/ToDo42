import Foundation
import Observation
import SwiftData
import CloudKit
import UIKit
import UserNotifications

enum PairRole: String, Codable {
    case chris
    case deena
}

struct PairProfile: Codable, Identifiable, Hashable {
    var pairID: String
    var roleRaw: String
    var inviteCode: String?
    var myName: String
    var partnerName: String

    var id: String { pairID }

    var role: PairRole? {
        get { PairRole(rawValue: roleRaw) }
        set { roleRaw = newValue?.rawValue ?? "" }
    }

    init(pairID: String, role: PairRole, inviteCode: String?, myName: String, partnerName: String) {
        self.pairID = pairID
        self.roleRaw = role.rawValue
        self.inviteCode = inviteCode
        self.myName = myName
        self.partnerName = partnerName
    }
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
    /// Known pairs on this phone (including the active one once persisted).
    var savedPairs: [PairProfile] = []
    /// True while the pair sheet is collecting a second (or first) invite/join.
    var isComposingNewPair = false
    /// Bumps when a local head photo changes so SwiftUI refreshes initials/photos.
    var headPhotoRevision = 0

    private let defaults = UserDefaults.standard
    private let appGroupDefaults = UserDefaults(suiteName: AppGroup.id)
    private let pairKey = "todo42.pairID"
    private let roleKey = "todo42.pairRole"
    private let codeKey = "todo42.inviteCode"
    private let myNameKey = "todo42.myName"
    private let partnerNameKey = "todo42.partnerName"
    private let pairHistoryKey = "todo42.pairIDHistory"
    private let savedPairsKey = "todo42.savedPairs"
    private let activePairAppGroupKey = "todo42.activePairID"

    var isPaired: Bool { pairID != nil && role != nil }
    var isApplyingRemote = false
    var hasMultiplePairs: Bool { savedPairs.count > 1 }

    var trimmedMyName: String {
        myName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedPartnerName: String {
        partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasNames: Bool {
        !trimmedMyName.isEmpty && !trimmedPartnerName.isEmpty
    }

    var myHeartLabel: String { trimmedMyName.isEmpty ? "YourName" : trimmedMyName }
    var partnerHeartLabel: String { trimmedPartnerName.isEmpty ? "PartnerName" : trimmedPartnerName }
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
        savedPairs = Self.loadSavedPairs(from: defaults, key: savedPairsKey)
        if savedPairs.isEmpty, let id = pairID, let role {
            savedPairs = [
                PairProfile(
                    pairID: id,
                    role: role,
                    inviteCode: inviteCode,
                    myName: myName,
                    partnerName: partnerName
                )
            ]
        } else {
            syncActiveFromSavedPairsIfNeeded()
        }
        mirrorActivePairToAppGroup()
    }

    var rememberedPairIDs: [String] {
        defaults.stringArray(forKey: pairHistoryKey) ?? []
    }

    /// Keep current list, clear the active slot so invite/join can add another pair.
    func beginAddPair() {
        snapshotActiveIntoSavedPairs()
        isComposingNewPair = true
        pairID = nil
        role = nil
        inviteCode = nil
        partnerName = ""
        statusMessage = ""
        persistLocal()
    }

    func cancelComposePair() {
        guard isComposingNewPair else { return }
        isComposingNewPair = false
        if let next = savedPairs.first {
            apply(profile: next)
        }
        persistLocal()
    }

    func switchToPair(_ id: String) {
        guard id != pairID else { return }
        guard let profile = savedPairs.first(where: { $0.pairID == id }) else { return }
        snapshotActiveIntoSavedPairs()
        apply(profile: profile)
        // Last-open first for share targeting.
        savedPairs.removeAll { $0.pairID == id }
        savedPairs.insert(profile, at: 0)
        isComposingNewPair = false
        persistLocal()
    }

    func switchToNextPair() {
        guard savedPairs.count > 1, let current = pairID else { return }
        let ids = savedPairs.map(\.pairID)
        guard let idx = ids.firstIndex(of: current) else { return }
        let next = ids[(idx + 1) % ids.count]
        switchToPair(next)
    }

    func unpair() {
        rememberPairID(pairID)
        if let id = pairID {
            savedPairs.removeAll { $0.pairID == id }
        }
        isComposingNewPair = false
        if let next = savedPairs.first {
            apply(profile: next)
        } else {
            pairID = nil
            role = nil
            inviteCode = nil
            statusMessage = ""
        }
        persistLocal()
    }

    func persist() {
        persistLocal()
        if isPaired {
            Task { await CloudSync.shared.uploadPairNames() }
        }
    }

    func persistLocal() {
        snapshotActiveIntoSavedPairs()
        rememberPairID(pairID)
        if let id = pairID {
            PairHeadPhotos.promoteDraft(to: id)
        }
        defaults.set(pairID, forKey: pairKey)
        defaults.set(role?.rawValue, forKey: roleKey)
        defaults.set(inviteCode, forKey: codeKey)
        defaults.set(myName, forKey: myNameKey)
        defaults.set(partnerName, forKey: partnerNameKey)
        if let data = try? JSONEncoder().encode(savedPairs) {
            defaults.set(data, forKey: savedPairsKey)
        }
        mirrorActivePairToAppGroup()
    }

    func headPairKey(for pairID: String? = nil) -> String {
        PairHeadPhotos.pairKey(for: pairID ?? self.pairID)
    }

    func headImageData(slot: PairHeadPhotos.Slot, pairID: String? = nil) -> Data? {
        _ = headPhotoRevision
        return PairHeadPhotos.load(pairKey: headPairKey(for: pairID), slot: slot)
    }

    func setHeadPhoto(slot: PairHeadPhotos.Slot, data: Data?, pairID: String? = nil) {
        PairHeadPhotos.save(pairKey: headPairKey(for: pairID), slot: slot, data: data)
        headPhotoRevision += 1
    }

    /// Call before createInvite/join when replacing the active CloudKit pair in place
    /// (e.g. “New invite code”), so the old id is not kept as a second pair.
    func discardActivePairSlotBeforeReplace() {
        guard !isComposingNewPair, let id = pairID else { return }
        savedPairs.removeAll { $0.pairID == id }
        rememberPairID(id)
    }

    func markComposeFinished() {
        isComposingNewPair = false
    }

    private func mirrorActivePairToAppGroup() {
        appGroupDefaults?.set(pairID, forKey: activePairAppGroupKey)
    }

    private func snapshotActiveIntoSavedPairs() {
        guard let id = pairID, let role else { return }
        let profile = PairProfile(
            pairID: id,
            role: role,
            inviteCode: inviteCode,
            myName: myName,
            partnerName: partnerName
        )
        if let idx = savedPairs.firstIndex(where: { $0.pairID == id }) {
            savedPairs[idx] = profile
        } else {
            savedPairs.insert(profile, at: 0)
        }
    }

    private func apply(profile: PairProfile) {
        pairID = profile.pairID
        role = profile.role
        inviteCode = profile.inviteCode
        myName = profile.myName
        partnerName = profile.partnerName
        statusMessage = ""
    }

    private func syncActiveFromSavedPairsIfNeeded() {
        guard let id = pairID else { return }
        if let profile = savedPairs.first(where: { $0.pairID == id }) {
            // Keep live fields; ensure list has current names on next persist.
            _ = profile
        } else if let role {
            savedPairs.insert(
                PairProfile(
                    pairID: id,
                    role: role,
                    inviteCode: inviteCode,
                    myName: myName,
                    partnerName: partnerName
                ),
                at: 0
            )
        }
    }

    private static func loadSavedPairs(from defaults: UserDefaults, key: String) -> [PairProfile] {
        guard let data = defaults.data(forKey: key),
              let pairs = try? JSONDecoder().decode([PairProfile].self, from: data) else {
            return []
        }
        return pairs
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
        // Adds must always upload. Skipping them while a pull is applying
        // leaves the item on this phone only; catch-up used to refuse to create it.
        if kind != "add" {
            guard !isApplyingRemote else { return }
        }
        if item.pairID.isEmpty, let pairID {
            item.pairID = pairID
        }
        item.updatedAt = Date()
        item.lastEditor = role?.rawValue ?? ""
        Task { await CloudSync.shared.upload(item, notifyKind: kind) }
    }

    func noteLocalReorder(moved: TodoItem, others: [TodoItem]) {
        guard !isApplyingRemote else { return }
        let now = Date()
        moved.updatedAt = now
        moved.lastEditor = role?.rawValue ?? ""
        for item in others {
            item.updatedAt = now
            item.lastEditor = role?.rawValue ?? ""
        }
        Task { await CloudSync.shared.uploadReorder(moved: moved, others: others) }
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
        if !session.isComposingNewPair {
            session.discardActivePairSlotBeforeReplace()
        }
        session.pairID = pairID
        session.role = .chris
        session.inviteCode = code
        session.markComposeFinished()
        session.persistLocal()
        try await subscribe()
        try await requestNotifications()
        await uploadCategoryTitles()
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
                throw SyncError.message("That code was not found. The person who sent the invite must tap “New invite code”, then send the new 6-digit code.")
            }
            throw SyncError.message(Self.friendlyMessage(error))
        }
        guard let pairID = record["pairID"] as? String, !pairID.isEmpty else {
            throw SyncError.message("That code was not found.")
        }
        let session = PairSession.shared
        if !session.isComposingNewPair {
            session.discardActivePairSlotBeforeReplace()
        }
        session.pairID = pairID
        session.role = .deena
        session.inviteCode = trimmed
        session.markComposeFinished()
        session.persistLocal()
        if let pair = try? await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)")) {
            let host = pair["hostName"] as? String ?? ""
            if !host.isEmpty {
                session.partnerName = host
            }
            CategoryNames.shared.applyRemoteJSON(pair[CategoryNames.cloudField] as? String)
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

    func uploadCategoryTitles() async {
        guard PairSession.shared.isPaired, let pairID = PairSession.shared.pairID else { return }
        let json = CategoryNames.shared.payloadJSON()
        guard !json.isEmpty else { return }
        await enqueue {
            do {
                let record = try await self.database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
                record[CategoryNames.cloudField] = json
                try await self.saveOverwriting(record)
            } catch {
                // Production schema may not have this field yet. Names still stay on the phone.
            }
        }
    }

    func sync(modelContext: ModelContext, allowCreate: Bool = false) async {
        guard PairSession.shared.isPaired else { return }
        await enqueue {
            do {
                try await self.ensureiCloud()
                try? await self.subscribe()
                try? await self.requestNotifications()
                ItemStore.migrateUnscopedItems(in: modelContext, to: PairSession.shared.pairID)
                ItemStore.purgeBlankTitleGhosts(in: modelContext)
                ItemStore.deduplicate(in: modelContext)
                let pairItems = ItemStore.items(forPair: PairSession.shared.pairID, in: modelContext)
                if allowCreate {
                    try await self.pushAll(pairItems, allowCreate: true)
                    try await self.pull(modelContext: modelContext)
                } else {
                    try await self.pull(modelContext: modelContext)
                    let afterPull = ItemStore.items(forPair: PairSession.shared.pairID, in: modelContext)
                    try await self.pushAll(afterPull, allowCreate: false)
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

    func uploadReorder(moved: TodoItem, others: [TodoItem]) async {
        guard PairSession.shared.isPaired else { return }
        await enqueue {
            do {
                for item in others {
                    try await self.saveItem(item, notifyKind: "")
                }
                try await self.saveItem(moved, notifyKind: "reorder")
                try? await self.registerItemIDs(([moved] + others).map(\.id.uuidString))
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
                let itemRecords = records.filter { self.recordKind($0) == .listItem }
                let extraRecords = records.filter { self.recordKind($0) == .extraPhoto }
                for record in itemRecords {
                    guard let itemID = record["itemID"] as? String, let uuid = UUID(uuidString: itemID) else { continue }
                    let recordPairID = (record["pairID"] as? String) ?? ""
                    if RemoteItemApply.isTombstone(notifyKind: record["notifyKind"] as? String) {
                        if let local = localByID[itemID] {
                            modelContext.delete(local)
                            localByID.removeValue(forKey: itemID)
                        }
                        continue
                    }
                    if let local = localByID[itemID] {
                        if local.pairID.isEmpty, !recordPairID.isEmpty {
                            local.pairID = recordPairID
                        }
                        self.apply(record, to: local)
                        continue
                    }
                    let title = RemoteItemApply.resolvedTitle(localTitle: "", remoteTitle: record["title"] as? String)
                    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let item = TodoItem(
                        title: title,
                        category: ItemCategory.parse(record["categoryRaw"] as? String ?? "places").first ?? .places,
                        urlString: record["urlString"] as? String,
                        notes: record["notes"] as? String ?? "",
                        sortOrder: CloudKitValues.intValue(record["sortOrder"]) ?? 0,
                        pairID: recordPairID.isEmpty ? session.pairID : recordPairID
                    )
                    item.id = uuid
                    self.apply(record, to: item)
                    modelContext.insert(item)
                    localByID[itemID] = item
                }
                for record in extraRecords {
                    guard let itemID = RemoteItemApply.extraItemID(
                        recordName: record.recordID.recordName,
                        itemID: record["itemID"] as? String
                    ) else { continue }
                    if let local = localByID[itemID] {
                        self.applyExtraPhoto(record, to: local)
                    }
                }
                try? modelContext.save()
                if session.isPaired {
                    let pairItems = ItemStore.items(forPair: session.pairID, in: modelContext)
                    try await self.pushAll(pairItems, allowCreate: true)
                }
                let total = ItemStore.items(forPair: session.pairID, in: modelContext).count
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
            let itemRecordID = CKRecord.ID(recordName: "item-\(id.uuidString)")
            do {
                _ = await self.tombstoneRemote(id)
                try await self.database.deleteRecord(withID: itemRecordID)
                try? await self.database.deleteRecord(withID: self.extraRecordID(for: id))
                try? await self.database.deleteRecord(withID: self.extra2RecordID(for: id))
                try? await self.database.deleteRecord(withID: self.extra3RecordID(for: id))
                try await self.removeItemID(id.uuidString)
                PairSession.shared.statusMessage = ""
            } catch let error as CKError where error.code == .unknownItem {
                try? await self.removeItemID(id.uuidString)
                PairSession.shared.statusMessage = ""
            } catch {
                // Partner is often not the CloudKit creator, so the record
                // delete fails. The tombstone still syncs so both lists drop it.
                if await self.tombstoneRemote(id) {
                    PairSession.shared.statusMessage = ""
                } else {
                    PairSession.shared.statusMessage = Self.friendlyMessage(error)
                }
            }
        }
    }

    private func tombstoneRemote(_ id: UUID) async -> Bool {
        let recordID = CKRecord.ID(recordName: "item-\(id.uuidString)")
        guard let record = try? await database.record(for: recordID) else { return false }
        record["notifyKind"] = "delete"
        record["notifyText"] = Self.pushBody(kind: "delete", title: record["title"] as? String ?? "")
        record["lastEditor"] = PairSession.shared.role?.rawValue ?? ""
        record["updatedAt"] = Date()
        do {
            try await saveOverwriting(record)
            try? await database.deleteRecord(withID: extraRecordID(for: id))
            try? await database.deleteRecord(withID: extra2RecordID(for: id))
            try? await database.deleteRecord(withID: extra3RecordID(for: id))
            return true
        } catch {
            return false
        }
    }

    func handleRemoteNotification(modelContext: ModelContext) async {
        await sync(modelContext: modelContext)
    }

    func inviteText(code: String) -> String {
        """
        Join \(PairSession.shared.trimmedMyName.isEmpty ? "me" : PairSession.shared.trimmedMyName) on Save4Two.

        1. Both of us install Save4Two from the App Store.
        2. Open the app and tap the red heart with a plus.
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
        CategoryNames.shared.applyRemoteJSON(pair[CategoryNames.cloudField] as? String)
        let listedIDs = (pair["itemIDs"] as? String ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
        let fetched = await fetchRemoteItemRecords(pairID: pairID, listedIDs: listedIDs)
        let remote = fetched.records.filter { recordKind($0) == .listItem }
        let extraRecords = fetched.records.filter { recordKind($0) == .extraPhoto }

        let session = PairSession.shared
        session.isApplyingRemote = true
        defer { session.isApplyingRemote = false }

        var localByID = ItemStore.keyedByID(ItemStore.allItems(in: modelContext))
        for record in remote {
            // Companion photo rows must never become home-list tiles.
            if RemoteItemApply.extraSlot(recordName: record.recordID.recordName) != nil {
                continue
            }
            guard let itemID = record["itemID"] as? String, let uuid = UUID(uuidString: itemID) else { continue }
            let notifyKind = record["notifyKind"] as? String
            if RemoteItemApply.isTombstone(notifyKind: notifyKind) {
                if let local = localByID[itemID], local.pairID.isEmpty || local.pairID == pairID {
                    modelContext.delete(local)
                    localByID.removeValue(forKey: itemID)
                    notifyRemoved(record)
                }
                continue
            }
            let remoteUpdated = record["updatedAt"] as? Date ?? .distantPast
            let local = localByID[itemID] ?? ItemStore.item(id: uuid, in: modelContext)
            if let local {
                // Never merge another list's row into this pair's pull.
                if !local.pairID.isEmpty, local.pairID != pairID {
                    continue
                }
                if local.pairID.isEmpty {
                    local.pairID = pairID
                }
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
                if RemoteItemApply.shouldApplyRemoteContent(
                    localUpdated: local.updatedAt ?? local.createdAt,
                    remoteUpdated: remoteUpdated,
                    localTitle: local.title,
                    remoteTitle: record["title"] as? String
                ) {
                    apply(record, to: local, hearts: false)
                    notifyUpdate(record, heartChanged: justHearted)
                } else if justHearted {
                    notifyUpdate(record, heartChanged: true)
                } else if RemoteItemApply.shouldApplyRemoteSort(
                    myRole: session.role?.rawValue,
                    lastEditor: record["lastEditor"] as? String,
                    notifyKind: notifyKind,
                    localSort: local.sortOrder,
                    remoteSort: CloudKitValues.intValue(record["sortOrder"]),
                    localUpdated: local.updatedAt ?? local.createdAt,
                    remoteUpdated: remoteUpdated
                ) {
                    local.sortOrder = CloudKitValues.intValue(record["sortOrder"]) ?? local.sortOrder
                    local.updatedAt = remoteUpdated
                    notifyUpdate(record, heartChanged: false)
                }
            } else {
                let title = RemoteItemApply.resolvedTitle(localTitle: "", remoteTitle: record["title"] as? String)
                guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let item = TodoItem(
                    title: title,
                    category: ItemCategory.parse(record["categoryRaw"] as? String ?? "places").first ?? .places,
                    urlString: record["urlString"] as? String,
                    notes: record["notes"] as? String ?? "",
                    sortOrder: CloudKitValues.intValue(record["sortOrder"]) ?? 0,
                    pairID: pairID
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
            guard let itemID = RemoteItemApply.extraItemID(
                recordName: record.recordID.recordName,
                itemID: record["itemID"] as? String
            ) else { continue }
            guard let local = localByID[itemID] ?? {
                guard let uuid = UUID(uuidString: itemID) else { return nil }
                return ItemStore.item(id: uuid, in: modelContext)
            }() else { continue }
            applyExtraPhoto(record, to: local)
        }
        if fetched.catalogComplete, !remote.isEmpty {
            let remoteIDs = Set(remote.compactMap { record -> String? in
                guard !RemoteItemApply.isTombstone(notifyKind: record["notifyKind"] as? String) else { return nil }
                return record["itemID"] as? String
            })
            let extrasByItemID = Set(extraRecords.compactMap { record -> String? in
                guard RemoteItemApply.extraSlot(recordName: record.recordID.recordName) == 1 else { return nil }
                return RemoteItemApply.extraItemID(
                    recordName: record.recordID.recordName,
                    itemID: record["itemID"] as? String
                )
            })
            let extra2ByItemID = Set(extraRecords.compactMap { record -> String? in
                guard RemoteItemApply.extraSlot(recordName: record.recordID.recordName) == 2 else { return nil }
                return RemoteItemApply.extraItemID(
                    recordName: record.recordID.recordName,
                    itemID: record["itemID"] as? String
                )
            })
            let extra3ByItemID = Set(extraRecords.compactMap { record -> String? in
                guard RemoteItemApply.extraSlot(recordName: record.recordID.recordName) == 3 else { return nil }
                return RemoteItemApply.extraItemID(
                    recordName: record.recordID.recordName,
                    itemID: record["itemID"] as? String
                )
            })
            for local in ItemStore.items(forPair: pairID, in: modelContext) {
                if remoteIDs.contains(local.id.uuidString) {
                    let remoteItem = remote.first {
                        ($0["itemID"] as? String) == local.id.uuidString
                    }
                    let remoteUpdated = remoteItem?["updatedAt"] as? Date
                        ?? remoteItem?.modificationDate
                        ?? .distantPast
                    if local.hasExtraPhoto, !extrasByItemID.contains(local.id.uuidString),
                       remoteUpdated >= (local.updatedAt ?? local.createdAt) {
                        local.extraImageData = nil
                    }
                    if local.hasExtraPhoto2, !extra2ByItemID.contains(local.id.uuidString),
                       remoteUpdated >= (local.updatedAt ?? local.createdAt) {
                        local.extraImageData2 = nil
                    }
                    if local.hasExtraPhoto3, !extra3ByItemID.contains(local.id.uuidString),
                       remoteUpdated >= (local.updatedAt ?? local.createdAt) {
                        local.extraImageData3 = nil
                    }
                    continue
                }
                if Date().timeIntervalSince(local.createdAt) < 180,
                   local.lastEditor == session.role?.rawValue || local.lastEditor.isEmpty {
                    continue
                }
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
        let missingExtra2 = listedIDs.filter { found["extra2-\($0)"] == nil }
        if !missingExtra2.isEmpty {
            for record in await fetchNamedRecords(missingExtra2.map { "extra2-\($0)" }) {
                found[record.recordID.recordName] = record
            }
        }
        let missingExtra3 = listedIDs.filter { found["extra3-\($0)"] == nil }
        if !missingExtra3.isEmpty {
            for record in await fetchNamedRecords(missingExtra3.map { "extra3-\($0)" }) {
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
        let pairID: String
        if !item.pairID.isEmpty {
            pairID = item.pairID
        } else if let active = PairSession.shared.pairID {
            pairID = active
            item.pairID = active
        } else {
            return
        }
        // Never re-tag another list onto the open pair's CloudKit records.
        if let active = PairSession.shared.pairID, pairID != active {
            return
        }
        let recordID = CKRecord.ID(recordName: "item-\(item.id.uuidString)")
        let wipedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if wipedTitle {
            // Do not push a blank title over iCloud. Hearts can still move,
            // and Chris's copy will republish the real title on catch-up.
            if let existing = try? await database.record(for: recordID) {
                switch PairSession.shared.role {
                case .chris:
                    existing["chrisHearted"] = item.chrisHearted ? 1 : 0
                case .deena:
                    existing["deenaHearted"] = item.deenaHearted ? 1 : 0
                case nil:
                    existing["chrisHearted"] = item.chrisHearted ? 1 : 0
                    existing["deenaHearted"] = item.deenaHearted ? 1 : 0
                }
                try? await saveOverwriting(existing)
            }
            await saveCompanionPhotos(for: item, pairID: pairID)
            return
        }
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            if notifyKind.isEmpty, shouldSkipCatchupPush(item, existing: existing) {
                // Still publish a local bottom photo that never made it to iCloud
                // (older builds dropped those uploads), without rewriting newer fields.
                if item.hasExtraPhoto || item.hasExtraPhoto2 || item.hasExtraPhoto3 {
                    await saveCompanionPhotos(for: item, pairID: pairID)
                }
                return
            }
            record = existing
        } else {
            guard RemoteItemApply.shouldCreateMissingRecord(
                allowCreate: allowCreate,
                notifyKind: notifyKind,
                title: item.title
            ) else { return }
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
        record["notifyKind"] = notifyKind
        if !notifyKind.isEmpty {
            record["notifyText"] = Self.pushBody(kind: notifyKind, title: item.title)
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
        await saveCompanionPhotos(for: item, pairID: pairID)
    }

    /// Extra photos sync through companion TDItem rows that reuse the known
    /// `image` asset field, so Production CloudKit does not need new image fields.
    private func extraRecordID(for itemID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "extra-\(itemID.uuidString)")
    }

    private func extra2RecordID(for itemID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "extra2-\(itemID.uuidString)")
    }

    private func extra3RecordID(for itemID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "extra3-\(itemID.uuidString)")
    }

    private func saveCompanionPhotos(for item: TodoItem, pairID: String) async {
        await saveCompanionPhoto(
            data: item.extraImageData,
            recordID: extraRecordID(for: item.id),
            item: item,
            pairID: pairID,
            sortOrder: -1,
            fileSuffix: "extra"
        )
        await saveCompanionPhoto(
            data: item.extraImageData2,
            recordID: extra2RecordID(for: item.id),
            item: item,
            pairID: pairID,
            sortOrder: -2,
            fileSuffix: "extra2"
        )
        await saveCompanionPhoto(
            data: item.extraImageData3,
            recordID: extra3RecordID(for: item.id),
            item: item,
            pairID: pairID,
            sortOrder: -3,
            fileSuffix: "extra3"
        )
    }

    private func saveCompanionPhoto(
        data: Data?,
        recordID: CKRecord.ID,
        item: TodoItem,
        pairID: String,
        sortOrder: Int,
        fileSuffix: String
    ) async {
        guard let extra = data, !extra.isEmpty else {
            try? await database.deleteRecord(withID: recordID)
            return
        }
        let record = (try? await database.record(for: recordID))
            ?? CKRecord(recordType: "TDItem", recordID: recordID)
        record["pairID"] = pairID
        record["itemID"] = item.id.uuidString
        record["sortOrder"] = sortOrder
        record["createdAt"] = item.createdAt
        record["updatedAt"] = item.updatedAt ?? item.createdAt
        record["lastEditor"] = item.lastEditor
        // Never leave list fields on companion rows — pull used to promote
        // titled extras into duplicate home-list tiles.
        record["title"] = nil
        record["urlString"] = nil
        record["notes"] = nil
        record["categoryRaw"] = nil
        record["chrisHearted"] = nil
        record["deenaHearted"] = nil
        record["isDone"] = nil
        record["notifyKind"] = nil
        record["notifyText"] = nil
        let extraURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id.uuidString)-\(fileSuffix).jpg")
        guard (try? extra.write(to: extraURL)) != nil else { return }
        record["image"] = CKAsset(fileURL: extraURL)
        try? await saveOverwriting(record)
    }

    private func applyExtraPhoto(_ record: CKRecord, to item: TodoItem) {
        if let asset = record["image"] as? CKAsset, let url = asset.fileURL,
           let data = try? Data(contentsOf: url), !data.isEmpty, data.count < 8_000_000 {
            switch RemoteItemApply.extraSlot(recordName: record.recordID.recordName) {
            case 3:
                item.extraImageData3 = data
            case 2:
                item.extraImageData2 = data
            default:
                item.extraImageData = data
            }
        }
    }

    private func recordKind(_ record: CKRecord) -> TDItemRecordKind {
        TDItemRecordKind.classify(
            recordName: record.recordID.recordName,
            title: record["title"] as? String,
            sortOrder: CloudKitValues.intValue(record["sortOrder"])
        )
    }

    private func apply(_ record: CKRecord, to item: TodoItem, hearts: Bool = true) {
        item.title = RemoteItemApply.resolvedTitle(
            localTitle: item.title,
            remoteTitle: record["title"] as? String
        )
        guard recordKind(record) == .listItem else { return }
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
        if RemoteItemApply.shouldRepublishTitle(
            localTitle: item.title,
            remoteTitle: existing["title"] as? String
        ) {
            return false
        }
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
        guard let pairID = PairSession.shared.pairID,
              let myRole = PairSession.shared.role else { return }
        let partnerRole = myRole == .chris ? PairRole.deena.rawValue : PairRole.chris.rawValue
        let prefix = pairID.prefix(8)
        let alertID = "todo42-alert-v4-\(prefix)-\(myRole.rawValue)"
        let silentID = "todo42-silent-v4-\(prefix)-\(myRole.rawValue)"

        let migrateKey = "todo42.pushSub.v4.\(prefix)"
        if !UserDefaults.standard.bool(forKey: migrateKey) {
            for oldID in [
                "todo42-tditem-\(prefix)",
                "todo42-tditem-all",
                "todo42-alert-\(prefix)-\(myRole.rawValue)",
            ] {
                try? await database.deleteSubscription(withID: oldID)
            }
            UserDefaults.standard.set(true, forKey: migrateKey)
        }

        let silentInfo = CKSubscription.NotificationInfo()
        silentInfo.shouldSendContentAvailable = true
        silentInfo.shouldBadge = false
        let silent = CKQuerySubscription(
            recordType: "TDItem",
            predicate: NSPredicate(format: "pairID == %@", pairID),
            subscriptionID: silentID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        silent.notificationInfo = silentInfo
        try? await database.save(silent)

        let notifyKinds = ["add", "heart", "edit", "reorder", "delete"]
        let predicates = [
            NSPredicate(format: "pairID == %@ AND lastEditor == %@ AND notifyKind IN %@", pairID, partnerRole, notifyKinds),
            NSPredicate(format: "pairID == %@ AND lastEditor == %@ AND sortOrder >= 0", pairID, partnerRole),
            NSPredicate(format: "pairID == %@ AND lastEditor == %@", pairID, partnerRole),
            NSPredicate(format: "pairID == %@", pairID),
        ]
        for predicate in predicates {
            let subscription = CKQuerySubscription(
                recordType: "TDItem",
                predicate: predicate,
                subscriptionID: alertID,
                options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
            )
            subscription.notificationInfo = Self.alertNotificationInfo()
            do {
                _ = try await database.save(subscription)
                return
            } catch {
                continue
            }
        }
    }

    private static func alertNotificationInfo() -> CKSubscription.NotificationInfo {
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.shouldBadge = false
        info.soundName = "default"
        info.title = "Save 4 Two"
        info.alertBody = "Your list was updated"
        return info
    }

    private static func pushBody(kind: String, title: String) -> String {
        let who = PairSession.shared.myHeartLabel
        let item = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = item.isEmpty ? "an item" : item
        switch kind {
        case "heart": return "\(who) hearted \(label)"
        case "add": return "\(who) added \(label)"
        case "reorder": return "\(who) reordered the list"
        case "delete": return "\(who) removed \(label)"
        default: return "\(who) updated \(label)"
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

    private func notifyRemoved(_ record: CKRecord) {
        guard recordKind(record) == .listItem else { return }
        let editor = record["lastEditor"] as? String ?? ""
        guard editor != PairSession.shared.role?.rawValue else { return }
        let who = PairSession.shared.displayName(forEditor: editor)
        let title = record["title"] as? String ?? "an item"
        postNotice(title: "\(who) removed an item", body: title)
    }

    private func notifyNew(_ record: CKRecord) {
        guard recordKind(record) == .listItem else { return }
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
        let kind = record["notifyKind"] as? String ?? ""
        if kind == "reorder" {
            postNotice(title: "\(who) reordered the list", body: title)
            return
        }
        if kind.isEmpty { return }
        postNotice(title: "\(who) updated an item", body: title)
    }

    private func postNotice(title: String, body: String) {
        // Lock-screen banners for a closed app come from CloudKit. Local
        // notices are only for when this phone is already open.
        guard UIApplication.shared.applicationState == .active else { return }
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
