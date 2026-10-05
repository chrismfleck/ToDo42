import Foundation
import Observation
import SwiftData
import CloudKit
import UIKit
import UserNotifications

enum PairRole: String, Codable {
    case chris
    case deena

    /// User-facing seat label. CloudKit still stores `chris` / `deena`.
    var seatLabel: String {
        switch self {
        case .chris: return "primary"
        case .deena: return "partner"
        }
    }
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
        // Only fill blanks. Blind overwrite let a third joiner rename the couple
        // (Chris saw “paired to Diane” after Diane wrote guestName).
        var changed = false
        if role == .deena {
            if trimmedMyName.isEmpty, !guestName.isEmpty {
                myName = guestName
                changed = true
            }
            if trimmedPartnerName.isEmpty, !hostName.isEmpty {
                partnerName = hostName
                changed = true
            }
        } else {
            if trimmedMyName.isEmpty, !hostName.isEmpty {
                myName = hostName
                changed = true
            }
            if trimmedPartnerName.isEmpty, !guestName.isEmpty {
                partnerName = guestName
                changed = true
            }
        }
        if changed {
            persistLocal()
        }
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
        // Always stamp locally first. Skipping the stamp while a pull runs let
        // catalog cleanup treat a just-added bottom photo as "missing remotely"
        // and delete it before the companion upload landed.
        if item.pairID.isEmpty, let pairID {
            item.pairID = pairID
        }
        if kind == "add" {
            let pair = item.pairID.isEmpty ? pairID : item.pairID
            DeletedItemLedger.allowAgain(pairID: pair, urlString: item.urlString, id: item.id)
        }
        item.updatedAt = Date()
        item.lastEditor = role?.rawValue ?? ""
        // Uploads are serialized on CloudSync's queue, so this waits for any
        // in-flight pull instead of dropping the edit.
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
    /// True while a sync body is running. Polling skips when set so Force sync
    /// is not stuck behind an endless queue of 2s refreshes.
    private(set) var isBusySyncing = false
    private var lastSubscribeAt: Date?

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
        if let sync = error as? SyncError {
            return sync.errorDescription ?? "Couldn't sync the list."
        }
        if let ck = error as? CKError {
            switch ck.code {
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                return "Couldn't reach iCloud. Try again in a moment."
            case .notAuthenticated:
                return "Sign in to iCloud on this iPhone so the lists can sync."
            case .quotaExceeded:
                return "iCloud storage is full on this Apple Account."
            case .permissionFailure:
                return "iCloud blocked a sync write. Both phones must use the same Apple Account iCloud login used to pair."
            case .unknownItem:
                return "That pair was not found in iCloud. Restore with the 6-digit invite code."
            case .serverRecordChanged:
                return "iCloud had a sync conflict. Tap Force sync now."
            case .limitExceeded, .partialFailure:
                return "iCloud rejected part of the sync. Tap Force sync now."
            case .invalidArguments:
                let detail = ck.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                if detail.isEmpty || detail.lowercased().contains("invalid arguments") {
                    return "iCloud rejected a field on sync. Update to latest build, then Force sync."
                }
                return "iCloud field error: \(detail)"
            default:
                return "Couldn't sync the list (iCloud \(ck.code.rawValue)). Try Force sync now."
            }
        }
        return "Couldn't sync the list. Try again in a moment."
    }

    /// Keys known to exist on Production `TDItem` / companions. Anything else is
    /// omitted on retry so a schema mismatch cannot block sync.
    private static let productionItemKeys: Set<String> = [
        "itemID", "pairID", "title", "urlString", "notes", "categoryRaw",
        "chrisHearted", "deenaHearted", "isDone", "sortOrder",
        "createdAt", "updatedAt", "lastEditor", "notifyKind", "image",
    ]

    private static let productionPairKeys: Set<String> = [
        "itemIDs", "hostName", "guestName", "createdAt",
    ]

    private func saveOverwriting(_ record: CKRecord) async throws {
        // changedKeys avoids re-sending unknown server fields. On rejection,
        // rebuild a slim record with only Production-safe keys and retry.
        do {
            try await performSaveOverwriting(record, policy: .changedKeys)
            return
        } catch let error as CKError where error.code == .invalidArguments || error.code == .partialFailure {
            let allowed = record.recordType == "TDPair"
                ? Self.productionPairKeys
                : Self.productionItemKeys
            let slim = (try? Self.systemFieldCopy(of: record))
                ?? CKRecord(recordType: record.recordType, recordID: record.recordID)
            for key in allowed {
                if let value = record[key] {
                    slim[key] = value
                }
            }
            do {
                try await performSaveOverwriting(slim, policy: .changedKeys)
                return
            } catch let retry as CKError where retry.code == .invalidArguments || retry.code == .partialFailure {
                // Last resort for items: drop the image asset (sometimes rejected).
                if record.recordType == "TDItem" {
                    let core = (try? Self.systemFieldCopy(of: record))
                        ?? CKRecord(recordType: record.recordType, recordID: record.recordID)
                    for key in Self.productionItemKeys where key != "image" {
                        if let value = record[key] {
                            core[key] = value
                        }
                    }
                    try await performSaveOverwriting(core, policy: .changedKeys)
                    return
                }
                throw retry
            }
        }
    }

    private func performSaveOverwriting(_ record: CKRecord, policy: CKModifyRecordsOperation.RecordSavePolicy) async throws {
        let outcome = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: policy
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

    /// Preserve CloudKit change tags so a slim retry does not 409.
    private static func systemFieldCopy(of record: CKRecord) throws -> CKRecord {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = true
        guard let copy = CKRecord(coder: unarchiver) else {
            throw SyncError.message("Couldn't prepare iCloud retry record.")
        }
        return copy
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

    /// New 6-digit code for the **same** shared list (re-invite). Does not create
    /// a second CloudKit pair or copy items.
    func rotateInviteCode() async throws -> String {
        try await ensureiCloud()
        guard let pairID = PairSession.shared.pairID, !pairID.isEmpty else {
            throw SyncError.message("Pair first, then you can send a new code.")
        }
        let code = String((0..<6).map { _ in "0123456789".randomElement()! })
        let codeRecord = CKRecord(recordType: "TDPairCode", recordID: CKRecord.ID(recordName: "code-\(code)"))
        codeRecord["pairID"] = pairID
        codeRecord["createdAt"] = Date()
        _ = try await database.modifyRecords(saving: [codeRecord], deleting: [], savePolicy: .allKeys)
        if let old = PairSession.shared.inviteCode, old != code {
            try? await database.deleteRecord(withID: CKRecord.ID(recordName: "code-\(old)"))
        }
        PairSession.shared.inviteCode = code
        PairSession.shared.persistLocal()
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
        let pair = try await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
        let host = (pair["hostName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let guest = (pair["guestName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard RemoteItemApply.canJoinExistingPair(
            myName: session.trimmedMyName,
            hostName: host,
            guestName: guest
        ) else {
            throw SyncError.message(
                "This list already has two people. For a separate list, your partner must tap Add a pair and send a new code — not the code from their other pair."
            )
        }
        session.pairID = pairID
        session.role = .deena
        session.inviteCode = trimmed
        session.markComposeFinished()
        if !host.isEmpty {
            session.partnerName = host
        }
        CategoryNames.shared.applyRemoteJSON(pair[CategoryNames.cloudField] as? String)
        // Only claim the open guest seat (or refresh the same guest re-joining).
        // Never replace an existing guest name with a third person.
        if guest.isEmpty || guest.caseInsensitiveCompare(session.trimmedMyName) == .orderedSame {
            pair["guestName"] = session.trimmedMyName
        }
        if session.trimmedPartnerName.isEmpty == false, host.isEmpty {
            pair["hostName"] = session.trimmedPartnerName
        }
        try await saveOverwriting(pair)
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

    func sync(
        modelContext: ModelContext,
        allowCreate: Bool = false,
        hintRecordIDs: [CKRecord.ID] = [],
        coalesce: Bool = true,
        preferCatalogFetch: Bool = false
    ) async {
        guard PairSession.shared.isPaired else { return }
        // Background polls coalesce onto the in-flight sync instead of queueing
        // forever (which froze Force sync / Restore on Build 165).
        if coalesce, isBusySyncing {
            await operationTail.value
            return
        }
        await enqueue {
            self.isBusySyncing = true
            defer { self.isBusySyncing = false }
            do {
                try await self.ensureiCloud()
                // Refresh push subscriptions every Force sync / first sync so
                // v6 partner-only alerts replace older “notify both phones” subs.
                let shouldRefreshSubs = preferCatalogFetch
                    || self.lastSubscribeAt.map { Date().timeIntervalSince($0) > 600 } ?? true
                if shouldRefreshSubs {
                    _ = try? await self.withTimeout(seconds: 10) {
                        try await self.subscribe()
                    }
                    try? await self.requestNotifications()
                    self.lastSubscribeAt = Date()
                }
                ItemStore.migrateUnscopedItems(in: modelContext, to: PairSession.shared.pairID)
                self.dropLedgerMatches(in: modelContext, pairID: PairSession.shared.pairID)
                ItemStore.purgeBlankTitleGhosts(in: modelContext)
                ItemStore.deduplicate(in: modelContext)
                ItemStore.deduplicateContentTwins(in: modelContext)
                // Strict pair scope for uploads — never push another list's rows
                // (or unscoped leftovers) into this pair's CloudKit catalog.
                let pairItems = ItemStore.items(
                    forPair: PairSession.shared.pairID,
                    in: modelContext,
                    includeUnscoped: false
                )
                if allowCreate {
                    try await self.pushAll(pairItems, allowCreate: true)
                    // Restore may create rows that were never catalogued — list them once.
                    try? await self.registerItemIDs(pairItems.map(\.id.uuidString))
                    try await self.pull(
                        modelContext: modelContext,
                        hintRecordIDs: hintRecordIDs,
                        preferCatalogFetch: preferCatalogFetch
                    )
                } else {
                    try await self.pull(
                        modelContext: modelContext,
                        hintRecordIDs: hintRecordIDs,
                        preferCatalogFetch: preferCatalogFetch
                    )
                    let afterPull = ItemStore.items(
                        forPair: PairSession.shared.pairID,
                        in: modelContext,
                        includeUnscoped: false
                    )
                    try await self.pushAll(afterPull, allowCreate: false)
                    // Re-try brand-new locals that never got an iCloud row (failed first
                    // upload). Does not recreate old partner zombies — only recent
                    // items we authored, and never over a delete tombstone.
                    try await self.pushMissingLocals(afterPull)
                }
                // Clear a prior failure banner once sync completes. Keep
                // success/diagnostic lines from upload / Force sync.
                let msg = PairSession.shared.statusMessage
                let keep = msg.hasPrefix("Saved")
                    || msg.hasPrefix("Pair …")
                    || msg.hasPrefix("Done")
                    || msg.hasPrefix("Restored")
                    || msg.hasPrefix("Syncing")
                if !keep {
                    PairSession.shared.statusMessage = ""
                }
            } catch {
                PairSession.shared.statusMessage = Self.friendlyMessage(error)
            }
        }
    }

    func upload(_ item: TodoItem, notifyKind: String) async {
        guard PairSession.shared.isPaired else { return }
        await enqueue {
            do {
                // Save the TDItem row FIRST. Registering the catalog id before
                // save left orphan catalog entries when Production rejected the
                // row (Chris saw catalog N↑ but fetch 3/5 — no item to download).
                // Partner pull still accepts provisional / push-hinted adds while
                // the post-save catalog register catches up.
                try await self.saveItem(item, notifyKind: notifyKind)
                do {
                    try await self.registerItemIDs([item.id.uuidString], retries: 5)
                    PairSession.shared.statusMessage = ""
                } catch {
                    PairSession.shared.statusMessage = notifyKind == "add"
                        ? "Saved item; catalog retry needed — tap Force sync."
                        : Self.friendlyMessage(error)
                }
            } catch {
                PairSession.shared.statusMessage = Self.friendlyMessage(error)
            }
        }
    }

    /// Short report so both phones can confirm they share the same CloudKit pair.
    /// Avoids unbounded CloudKit queries — those hung Force sync on “Syncing…”.
    func syncDiagnostics() async -> String {
        guard let pairID = PairSession.shared.pairID else {
            return "Not paired — Restore with the 6-digit code first."
        }
        let role = PairSession.shared.role?.seatLabel ?? "?"
        let code = PairSession.shared.inviteCode ?? "no-code"
        let short = String(pairID.suffix(8))
        do {
            try await ensureiCloud()
            let pair = try await withTimeout(seconds: 12) {
                try await self.database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
            }
            let live = CloudKitValues.liveItemIDs(in: pair["itemIDs"] as? String)
            let sample = Array(live.suffix(5))
            let fetched = await fetchNamedRecords(sample.map { "item-\($0)" })
            let queryMode = lastPairQuerySucceeded ? "query ok" : (lastUsedCatalogFetch ? "catalog fetch" : "query fallback")
            var line = "Pair …\(short) · \(role) · code \(code) · catalog \(live.count) · fetch \(fetched.count)/\(sample.count) · \(queryMode)"
            if lastPullCatalogCount > 0 {
                line += " · pulled \(lastPullFetchedCount)/\(lastPullCatalogCount)"
            }
            if !sample.isEmpty, fetched.count < sample.count {
                line += "\nSome catalog ids have no item row — partner should Force sync to re-upload."
            } else if lastPullCatalogCount > 0, lastPullFetchedCount + 5 < lastPullCatalogCount {
                line += "\nPartial catalog download — Force sync again on both phones."
            }
            return line
        } catch {
            return "Pair …\(short) · \(role) · code \(code) · \(Self.friendlyMessage(error))"
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

                // Re-attach pairing from the invite code so the list stays in sync
                // (restore alone used to leave the phone unpaired).
                let trimmedCode = oldCode.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedCode.count == 6, let reattached = await self.reattachPair(fromInviteCode: trimmedCode) {
                    _ = reattached
                }

                var localByID = ItemStore.keyedByID(ItemStore.allItems(in: modelContext))
                let itemRecords = records.filter { self.recordKind($0) == .listItem }
                let extraRecords = records.filter { self.recordKind($0) == .extraPhoto }
                for record in itemRecords {
                    guard RemoteItemApply.extraSlot(recordName: record.recordID.recordName) == nil else { continue }
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
                    let resolvedPair = recordPairID.isEmpty ? (session.pairID ?? "") : recordPairID
                    let item = TodoItem(
                        title: title,
                        category: ItemCategory.parse(record["categoryRaw"] as? String ?? "places").first ?? .places,
                        urlString: record["urlString"] as? String,
                        notes: record["notes"] as? String ?? "",
                        sortOrder: CloudKitValues.intValue(record["sortOrder"]) ?? 0,
                        pairID: resolvedPair
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
                    ItemStore.migrateUnscopedItems(in: modelContext, to: session.pairID)
                    let pairItems = ItemStore.items(forPair: session.pairID, in: modelContext)
                    try await self.pushAll(pairItems, allowCreate: true)
                }
                let total = ItemStore.items(forPair: session.pairID, in: modelContext).count
                if records.isEmpty {
                    session.statusMessage = result.emptyMessage
                } else if session.isPaired {
                    session.statusMessage = "Restored \(total) item\(total == 1 ? "" : "s") and reconnected the pair."
                } else {
                    session.statusMessage = "Restored \(total) item\(total == 1 ? "" : "s"). Enter the 6-digit code under Join so sync stays on."
                }
            } catch {
                PairSession.shared.statusMessage = Self.friendlyMessage(error)
            }
        }
    }

    /// Puts this phone back on the pair that owned `code` (host if names match, else guest).
    private func reattachPair(fromInviteCode code: String) async -> String? {
        guard let codeRecord = try? await database.record(for: CKRecord.ID(recordName: "code-\(code)")),
              let pairID = codeRecord["pairID"] as? String,
              !pairID.isEmpty
        else { return nil }

        let session = PairSession.shared
        // Remember role before discardActivePairSlotBeforeReplace drops the slot.
        // Defaulting both phones to .chris after Restore broke partner push filters.
        let priorRole: PairRole? = {
            if let saved = session.savedPairs.first(where: { $0.pairID == pairID })?.role {
                return saved
            }
            if session.pairID == pairID { return session.role }
            if session.inviteCode == code { return session.role }
            return nil
        }()

        if !session.isComposingNewPair {
            session.discardActivePairSlotBeforeReplace()
        }
        session.pairID = pairID
        session.inviteCode = code

        var role: PairRole = priorRole ?? .chris
        if let pair = try? await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)")) {
            let host = (pair["hostName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let guest = (pair["guestName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let me = session.trimmedMyName
            let partner = session.trimmedPartnerName
            if priorRole == nil {
                if !me.isEmpty, me.caseInsensitiveCompare(guest) == .orderedSame {
                    role = .deena
                } else if !me.isEmpty, me.caseInsensitiveCompare(host) == .orderedSame {
                    role = .chris
                } else if !partner.isEmpty, partner.caseInsensitiveCompare(host) == .orderedSame {
                    role = .deena
                } else if !partner.isEmpty, partner.caseInsensitiveCompare(guest) == .orderedSame {
                    role = .chris
                } else {
                    role = .chris
                }
            }
            if role == .chris {
                if session.trimmedMyName.isEmpty, !host.isEmpty { session.myName = host }
                if session.trimmedPartnerName.isEmpty, !guest.isEmpty { session.partnerName = guest }
            } else {
                if session.trimmedMyName.isEmpty, !guest.isEmpty { session.myName = guest }
                if session.trimmedPartnerName.isEmpty, !host.isEmpty { session.partnerName = host }
            }
            CategoryNames.shared.applyRemoteJSON(pair[CategoryNames.cloudField] as? String)
        }
        session.role = role
        session.markComposeFinished()
        session.persistLocal()
        try? await subscribe()
        try? await requestNotifications()
        return pairID
    }

    func deleteRemote(_ id: UUID) async {
        guard PairSession.shared.isPaired else { return }
        await enqueue {
            // Two co-writable signals, saved separately. `deletedIDs` is a newer
            // field and Production CloudKit can reject it. The `x:` mark lives
            // in `itemIDs`, which already exists, so a partner on this build
            // still sees the delete when that field save fails. The row
            // tombstone works only for the record's creator.
            try? await self.addDeletedIDs([id.uuidString])
            try? await self.markCatalogDeleted([id.uuidString])
            _ = await self.tombstoneRemote(id)
            PairSession.shared.statusMessage = ""
        }
    }

    private func addDeletedIDs(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await mutatePairRecord { record in
            let merged = CloudKitValues.mergedDeletedIDs(record["deletedIDs"] as? String, adding: ids)
            guard merged != (record["deletedIDs"] as? String ?? "") else { return false }
            record["deletedIDs"] = merged
            return true
        }
    }

    private func tombstoneRemote(_ id: UUID) async -> Bool {
        let recordID = CKRecord.ID(recordName: "item-\(id.uuidString)")
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            if RemoteItemApply.isTombstone(notifyKind: existing["notifyKind"] as? String) {
                return true
            }
            record = existing
        } else {
            // Item never made it to iCloud (or was hard-deleted by an older build).
            // Still write a tombstone so the partner’s catch-up push cannot recreate it.
            record = CKRecord(recordType: "TDItem", recordID: recordID)
            record["itemID"] = id.uuidString
            record["pairID"] = PairSession.shared.pairID ?? ""
            record["title"] = ""
            record["chrisHearted"] = 0
            record["deenaHearted"] = 0
            record["isDone"] = 0
            record["sortOrder"] = 0
            record["createdAt"] = Date()
        }
        record["notifyKind"] = "delete"
        // Do not write notifyText — Production CloudKit may not have that field
        // (invalidArguments was failing Force sync on both phones).
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

    func handleRemoteNotification(
        modelContext: ModelContext,
        userInfo: [AnyHashable: Any]? = nil
    ) async {
        var hintIDs: [CKRecord.ID] = []
        if let userInfo,
           let note = CKQueryNotification(fromRemoteNotificationDictionary: userInfo),
           let recordID = note.recordID {
            hintIDs.append(recordID)
        }
        await sync(modelContext: modelContext, hintRecordIDs: hintIDs)
    }

    func inviteText(code: String) -> String {
        """
        Join \(PairSession.shared.trimmedMyName.isEmpty ? "me" : PairSession.shared.trimmedMyName) on Save4Two.

        1. Install Save4Two from the App Store:
        https://apps.apple.com/us/app/save4two/id6806054108
        2. Open the app and tap the red heart with a plus.
        3. Choose “I have a code” and enter: \(code)

        Stay signed in to iCloud on your iPhone so our lists can sync.
        """
    }

    private func pull(
        modelContext: ModelContext,
        hintRecordIDs: [CKRecord.ID] = [],
        preferCatalogFetch: Bool = false
    ) async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        let pair: CKRecord
        do {
            pair = try await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
        } catch let error as CKError where error.code == .unknownItem {
            throw SyncError.message(
                "That pair was not found in iCloud. Restore with the 6-digit invite code."
            )
        }
        PairSession.shared.applyRemoteNames(
            host: pair["hostName"] as? String,
            guest: pair["guestName"] as? String
        )
        CategoryNames.shared.applyRemoteJSON(pair[CategoryNames.cloudField] as? String)
        let catalogRaw = pair["itemIDs"] as? String ?? ""
        let listedIDs = CloudKitValues.liveItemIDs(in: catalogRaw)
        let catalogIDs = Set(listedIDs)
        // Anything here must never be shown, inserted, or healed. The pair
        // record's deletedIDs field, the `x:` marks inside itemIDs, and this
        // phone's own delete ledger are all authoritative.
        var deletedIDs = Set(
            (pair["deletedIDs"] as? String ?? "")
                .split(separator: ",")
                .map(String.init)
                .filter { !$0.isEmpty }
        )
        deletedIDs.formUnion(CloudKitValues.deletedIDs(in: catalogRaw))
        deletedIDs.formUnion(DeletedItemLedger.ids(pairID: pairID))
        let fetched = await fetchRemoteItemRecords(
            pairID: pairID,
            listedIDs: listedIDs,
            hintRecordIDs: hintRecordIDs,
            preferCatalogFetch: preferCatalogFetch
        )
        let remote = fetched.records.filter { recordKind($0) == .listItem }
        let extraRecords = fetched.records.filter { recordKind($0) == .extraPhoto }
        let hintNames = Set(hintRecordIDs.map(\.recordName))
        // When the pair catalog is known and non-empty, CloudKit rows that are
        // NOT listed are usually orphans from older hard-deletes — but a brand-
        // new add can also miss the catalog for a moment (registerItemIDs races
        // or fails). Authoritative deletes are already filtered via deletedIDs /
        // x: marks / the local ledger above; recent live rows are accepted below.
        let catalogReady = fetched.catalogComplete && !listedIDs.isEmpty

        let session = PairSession.shared
        session.isApplyingRemote = true
        defer { session.isApplyingRemote = false }

        var localByID = ItemStore.keyedByID(ItemStore.allItems(in: modelContext))
        var idsToHeal: [String] = []
        var idsToStrip: [String] = []
        for record in remote {
            // Companion photo rows must never become home-list tiles.
            if RemoteItemApply.extraSlot(recordName: record.recordID.recordName) != nil {
                continue
            }
            guard let itemID = record["itemID"] as? String, let uuid = UUID(uuidString: itemID) else { continue }
            // Authoritatively deleted on the shared pair record — never revive it,
            // regardless of who owns the (creator-only) item row.
            if deletedIDs.contains(itemID) {
                if let local = localByID[itemID], local.pairID.isEmpty || local.pairID == pairID {
                    modelContext.delete(local)
                    localByID.removeValue(forKey: itemID)
                    notifyRemoved(record)
                }
                if catalogIDs.contains(itemID) { idsToStrip.append(itemID) }
                continue
            }
            if DeletedItemLedger.containsURL(pairID: pairID, urlString: record["urlString"] as? String) {
                DeletedItemLedger.record(pairID: pairID, id: uuid, urlString: record["urlString"] as? String)
                if let local = localByID[itemID], local.pairID.isEmpty || local.pairID == pairID {
                    modelContext.delete(local)
                    localByID.removeValue(forKey: itemID)
                }
                idsToStrip.append(itemID)
                continue
            }
            let notifyKind = record["notifyKind"] as? String
            if RemoteItemApply.isTombstone(notifyKind: notifyKind) {
                if let local = localByID[itemID], local.pairID.isEmpty || local.pairID == pairID {
                    modelContext.delete(local)
                    localByID.removeValue(forKey: itemID)
                    notifyRemoved(record)
                }
                continue
            }
            if catalogReady, !catalogIDs.contains(itemID) {
                // Off the shared catalog. Deletes are already handled above via
                // deletedIDs / x: marks / ledger / tombstones. A live row here is
                // almost always a brand-new add whose registerItemIDs has not
                // landed yet. Accept:
                //   • push-hinted rows
                //   • rows last-edited by the partner (even if roles were wrong)
                //   • recent / notifyKind=="add" provisional rows
                // Leave older non-hinted own-side orphans alone so pre-tombstone
                // hard-deletes stay gone.
                let created = record["createdAt"] as? Date
                    ?? record["updatedAt"] as? Date
                    ?? .distantPast
                let hinted = hintNames.contains(record.recordID.recordName)
                    || hintNames.contains("item-\(itemID)")
                let editor = (record["lastEditor"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let myRole = (session.role?.rawValue ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let fromPartner = !editor.isEmpty && editor != myRole
                if hinted
                    || fromPartner
                    || RemoteItemApply.isProvisionalCatalogAdd(
                        notifyKind: notifyKind,
                        createdAt: created
                    )
                {
                    idsToHeal.append(itemID)
                    // fall through — merge/insert below
                } else {
                    continue
                }
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
                // Never revive a CloudKit orphan the catalog already dropped,
                // unless it is a provisional new add we are healing above.
                if catalogReady, !catalogIDs.contains(itemID),
                   !idsToHeal.contains(itemID) {
                    continue
                }
                if DeletedItemLedger.containsURL(pairID: pairID, urlString: record["urlString"] as? String) {
                    DeletedItemLedger.record(pairID: pairID, id: uuid, urlString: record["urlString"] as? String)
                    idsToStrip.append(itemID)
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
                let idString = local.id.uuidString
                if deletedIDs.contains(idString)
                    || DeletedItemLedger.containsURL(pairID: pairID, urlString: local.urlString) {
                    if DeletedItemLedger.containsURL(pairID: pairID, urlString: local.urlString) {
                        DeletedItemLedger.record(pairID: pairID, id: local.id, urlString: local.urlString)
                    }
                    if catalogIDs.contains(idString) {
                        idsToStrip.append(idString)
                    }
                    modelContext.delete(local)
                    continue
                }
                if catalogReady, !catalogIDs.contains(idString) {
                    // Off the shared catalog — this is the ambiguous case that
                    // caused both "new items vanish" and "deleted items come
                    // back". Resolve it authoritatively with a strongly-consistent
                    // per-record fetch (CloudKit record fetches are consistent;
                    // the catalog string and queries are not).
                    //
                    // Already pulled live this pass (partner add notification but
                    // catalog register still racing) — never delete; heal instead.
                    if remoteIDs.contains(idString) {
                        idsToHeal.append(idString)
                        continue
                    }
                    let recordID = CKRecord.ID(recordName: "item-\(idString)")
                    if let row = try? await database.record(for: recordID) {
                        if RemoteItemApply.isTombstone(notifyKind: row["notifyKind"] as? String) {
                            // Genuinely deleted — drop it and never re-list it.
                            modelContext.delete(local)
                            continue
                        }
                        // A live row that merely fell off the catalog — re-list it.
                        idsToHeal.append(idString)
                        continue
                    }
                    // No row on the server at all (or a transient fetch miss).
                    if RemoteItemApply.isOwnEdit(lastEditor: local.lastEditor, myRole: session.role?.rawValue) {
                        // Our own add whose first upload never landed — keep it
                        // (do not delete a brand-new item that just hasn't synced).
                        idsToHeal.append(idString)
                        continue
                    }
                    // Partner add: a failed record fetch used to wipe the row we
                    // just inserted from the same pull (banner fired, list empty).
                    let recentPartner = Date().timeIntervalSince(local.createdAt) < 48 * 3600
                        || Date().timeIntervalSince(local.updatedAt ?? local.createdAt) < 48 * 3600
                    if recentPartner {
                        idsToHeal.append(idString)
                        continue
                    }
                    // Older partner-authored and gone from both catalog and server.
                    modelContext.delete(local)
                    continue
                }
                if remoteIDs.contains(idString) {
                    let remoteItem = remote.first {
                        ($0["itemID"] as? String) == idString
                    }
                    let remoteUpdated = remoteItem?["updatedAt"] as? Date
                        ?? remoteItem?.modificationDate
                        ?? .distantPast
                    let localUpdated = local.updatedAt ?? local.createdAt
                    // Item record save and companion photo save are not atomic.
                    // A pull that sees the updated item but not the companion yet
                    // must not erase a bottom photo we just added. Only clear when
                    // the remote item is strictly newer (partner removed it) and
                    // we were not the last editor.
                    let remoteClearlyNewer = remoteUpdated > localUpdated
                    let iAmLastEditor = local.lastEditor == session.role?.rawValue
                        && !(session.role?.rawValue ?? "").isEmpty
                    if remoteClearlyNewer, !iAmLastEditor {
                        if local.hasExtraPhoto, !extrasByItemID.contains(idString) {
                            local.extraImageData = nil
                        }
                        if local.hasExtraPhoto2, !extra2ByItemID.contains(idString) {
                            local.extraImageData2 = nil
                        }
                        if local.hasExtraPhoto3, !extra3ByItemID.contains(idString) {
                            local.extraImageData3 = nil
                        }
                    }
                    continue
                }
                // Missing from the remote query but still in the catalog: keep
                // local so catch-up / pushMissingLocals can upload it. Removals
                // require an explicit tombstone or catalog drop above.
            }
        }
        // Re-read the ledger. A delete can land while this pull is awaiting
        // iCloud, and the snapshot above would otherwise insert the item again.
        let freshDeleted = Set(DeletedItemLedger.ids(pairID: pairID))
        var stripIDs = Set(idsToStrip)
            .union(deletedIDs.intersection(catalogIDs))
            .union(freshDeleted.intersection(catalogIDs))
        for local in ItemStore.items(forPair: pairID, in: modelContext) {
            let idString = local.id.uuidString
            let urlHit = DeletedItemLedger.containsURL(pairID: pairID, urlString: local.urlString)
            guard freshDeleted.contains(idString) || urlHit else { continue }
            if urlHit {
                DeletedItemLedger.record(pairID: pairID, id: local.id, urlString: local.urlString)
            }
            modelContext.delete(local)
            stripIDs.insert(idString)
        }
        let healIDs = Set(idsToHeal).subtracting(stripIDs).subtracting(freshDeleted)
        if !healIDs.isEmpty {
            try? await registerItemIDs(Array(healIDs))
        }
        if !stripIDs.isEmpty {
            // Partner builds that do not understand deletes merge the id back
            // into the catalog and can overwrite a tombstone. Put the mark back
            // and tombstone again so the row does not stay listed.
            try? await markCatalogDeleted(Array(stripIDs))
            for id in stripIDs {
                guard let uuid = UUID(uuidString: id) else { continue }
                _ = await tombstoneRemote(uuid)
            }
        }
        try? modelContext.save()
    }

    private func pushAll(_ items: [TodoItem], allowCreate: Bool) async throws {
        // One bad row must not fail the whole sync (that left a sticky
        // "Couldn't sync" banner on the home screen).
        for item in items {
            do {
                try await saveItem(item, notifyKind: "", allowCreate: allowCreate)
            } catch {
                continue
            }
        }
        // Do NOT register every local ID on catch-up. That merged deleted items
        // back into pair.itemIDs whenever the partner still held a local copy,
        // which made old deletes reappear on the other phone.
    }

    /// Upload locals that have no CloudKit row yet (first push failed / raced).
    /// Skips older rows so a partner’s leftover copy of a hard-deleted item is
    /// not resurrected as a brand-new record.
    private func pushMissingLocals(_ items: [TodoItem]) async throws {
        let role = PairSession.shared.role?.rawValue ?? ""
        let now = Date()
        var uploaded: [String] = []
        for item in items {
            if DeletedItemLedger.contains(pairID: item.pairID, id: item.id.uuidString) { continue }
            if DeletedItemLedger.containsURL(pairID: item.pairID, urlString: item.urlString) { continue }
            let mine = item.lastEditor.isEmpty || item.lastEditor == role
            // Wider window so Force sync can repair “some items miss” after a
            // failed photo upload from earlier in the day / weekend.
            let recent = now.timeIntervalSince(item.createdAt) < 7 * 24 * 3600
            guard mine, recent else { continue }
            let recordID = CKRecord.ID(recordName: "item-\(item.id.uuidString)")
            if let existing = try? await database.record(for: recordID) {
                if RemoteItemApply.isTombstone(notifyKind: existing["notifyKind"] as? String) {
                    // Partner (or we) already deleted this — drop the local leftover.
                    continue
                }
                // Row exists but may be missing its photo — best-effort attach.
                if item.hasAnyPhotos || (item.imageData?.isEmpty == false) {
                    try? await saveItem(item, notifyKind: "", allowCreate: false)
                }
                continue
            }
            do {
                try await saveItem(item, notifyKind: "add", allowCreate: true)
                uploaded.append(item.id.uuidString)
            } catch {
                continue
            }
        }
        if !uploaded.isEmpty {
            try? await registerItemIDs(uploaded)
        }
    }

    private func fetchRemoteItemRecords(
        pairID: String,
        listedIDs: [String],
        hintRecordIDs: [CKRecord.ID] = [],
        preferCatalogFetch: Bool = false
    ) async -> (records: [CKRecord], catalogComplete: Bool) {
        var found: [String: CKRecord] = [:]
        var catalogComplete = false

        let pairQuery = CKQuery(
            recordType: "TDItem",
            predicate: NSPredicate(format: "pairID == %@", pairID)
        )
        var pairQueryOK = false
        // Force sync skips the pairID query — it often hangs/times out on
        // Production and burned the whole sync before catalog downloads finished.
        if !preferCatalogFetch {
            do {
                let queried = try await withTimeout(seconds: 8) {
                    try await self.queryAll(pairQuery)
                }
                pairQueryOK = true
                catalogComplete = true
                for record in queried {
                    found[record.recordID.recordName] = record
                }
            } catch {
                pairQueryOK = false
            }
        }

        // Do NOT fall back to querying every TDItem in the public DB — that can
        // hang Force sync / Restore for minutes on a non-moving spinner.

        // Push payloads name the changed record. Query indexes can lag seconds
        // behind a save, so the partner's pull would miss the brand-new TDItem
        // without this strongly-consistent named fetch.
        let hintNames = hintRecordIDs.map(\.recordName).filter { found[$0] == nil }
        if !hintNames.isEmpty {
            for record in await fetchNamedRecords(hintNames) {
                if let pid = record["pairID"] as? String, !pid.isEmpty, pid != pairID {
                    continue
                }
                found[record.recordID.recordName] = record
            }
        }

        // Named-fetch catalog ids the query missed. When the pairID query fails
        // (or Force sync asks for catalog-first), fetch the shared catalog by id.
        let missing = listedIDs.filter { found["item-\($0)"] == nil }
        let refreshNames: [String]
        if pairQueryOK {
            refreshNames = Array(Set(missing + Array(listedIDs.suffix(30))))
        } else if listedIDs.count <= 400 {
            refreshNames = Array(Set(missing + listedIDs))
        } else {
            refreshNames = Array(Set(missing + Array(listedIDs.suffix(80))))
        }
        if !refreshNames.isEmpty {
            for record in await fetchNamedRecords(refreshNames.map { "item-\($0)" }) {
                found[record.recordID.recordName] = record
            }
        }
        // Second pass for catalog ids still missing (CloudKit eventually
        // consistent after a partner save — one miss used to drop new items).
        let stillMissing = listedIDs.filter { found["item-\($0)"] == nil }
        if !stillMissing.isEmpty, stillMissing.count <= 80 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            for record in await fetchNamedRecords(stillMissing.map { "item-\($0)" }) {
                found[record.recordID.recordName] = record
            }
        }
        // Extra photos only for list items we actually downloaded — fetching
        // extras for every catalog id made Force sync crawl for minutes.
        let fetchedListIDs = found.values.compactMap { record -> String? in
            guard recordKind(record) == .listItem else { return nil }
            return record["itemID"] as? String
        }
        let missingExtras = fetchedListIDs.filter { found["extra-\($0)"] == nil }
        if !missingExtras.isEmpty {
            for record in await fetchNamedRecords(missingExtras.map { "extra-\($0)" }) {
                found[record.recordID.recordName] = record
            }
        }
        let missingExtra2 = fetchedListIDs.filter { found["extra2-\($0)"] == nil }
        if !missingExtra2.isEmpty {
            for record in await fetchNamedRecords(missingExtra2.map { "extra2-\($0)" }) {
                found[record.recordID.recordName] = record
            }
        }
        let missingExtra3 = fetchedListIDs.filter { found["extra3-\($0)"] == nil }
        if !missingExtra3.isEmpty {
            for record in await fetchNamedRecords(missingExtra3.map { "extra3-\($0)" }) {
                found[record.recordID.recordName] = record
            }
        }
        lastPairQuerySucceeded = pairQueryOK
        lastUsedCatalogFetch = preferCatalogFetch
        let listItems = found.values.filter { recordKind($0) == .listItem }.count
        lastPullCatalogCount = listedIDs.count
        lastPullFetchedCount = listItems
        return (Array(found.values), catalogComplete || !listedIDs.isEmpty)
    }

    /// For Force sync diagnostics — false when Production pairID query failed.
    private(set) var lastPairQuerySucceeded = true
    /// True when the last pull skipped the pairID query and used catalog ids.
    private(set) var lastUsedCatalogFetch = false
    private(set) var lastPullCatalogCount = 0
    private(set) var lastPullFetchedCount = 0

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
        var pages = 0
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
            pages += 1
            // Safety: never page forever on a stuck public-DB cursor.
            if pages >= 20 { break }
        } while cursor != nil
        return records
    }

    /// Race an iCloud call against a deadline so Force sync cannot spin forever.
    private func withTimeout<T>(
        seconds: TimeInterval,
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { @MainActor in
                try await operation()
            }
            group.addTask {
                let ns = UInt64(max(1, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                throw SyncError.message("iCloud timed out. Tap Force sync again.")
            }
            guard let value = try await group.next() else {
                throw SyncError.message("iCloud timed out. Tap Force sync again.")
            }
            group.cancelAll()
            return value
        }
    }

    private func fetchNamedRecords(_ names: [String]) async -> [CKRecord] {
        var records: [CKRecord] = []
        var got = Set<String>()
        let ids = names.map { CKRecord.ID(recordName: $0) }
        var start = 0
        while start < ids.count {
            let end = min(start + 50, ids.count)
            let batch = Array(ids[start..<end])
            if let result = try? await database.records(for: batch) {
                for id in batch {
                    if let record = try? result[id]?.get(),
                       got.insert(id.recordName).inserted {
                        records.append(record)
                    }
                }
            }
            let miss = batch.filter { !got.contains($0.recordName) }
            if !miss.isEmpty {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let result = try? await database.records(for: miss) {
                    for id in miss {
                        if let record = try? result[id]?.get(),
                           got.insert(id.recordName).inserted {
                            records.append(record)
                        }
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
        if DeletedItemLedger.contains(pairID: pairID, id: item.id.uuidString) {
            return
        }
        let wipedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if wipedTitle {
            // Do not push a blank title over iCloud. Hearts can still move,
            // and Chris's copy will republish the real title on catch-up.
            if let existing = try? await database.record(for: recordID) {
                let remotePair = (existing["pairID"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !remotePair.isEmpty, remotePair != pairID {
                    return
                }
                // Never write over a tombstone — the delete must stay deleted.
                if RemoteItemApply.shouldSkipSaveOverTombstone(existingNotifyKind: existing["notifyKind"] as? String) {
                    return
                }
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
            let remotePair = (existing["pairID"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // item-<uuid> ids are global in the public DB. Never rewrite another
            // list's row onto this pair (that is how Diane inherited Chris/Deena).
            if !remotePair.isEmpty, remotePair != pairID {
                return
            }
            // Never resurrect a deleted item: if the server copy is a tombstone,
            // the delete wins over any local catch-up push or edit.
            if RemoteItemApply.shouldSkipSaveOverTombstone(existingNotifyKind: existing["notifyKind"] as? String) {
                return
            }
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
        // Catch-up pushes pass an empty notifyKind — do not wipe "add" on the
        // server or the partner's provisional-catalog accept can miss the row.
        // Never write notifyText: Production schema may reject it and break sync.
        if !notifyKind.isEmpty {
            record["notifyKind"] = notifyKind
        }
        // Always land the text row first. Attaching a large photo in the same
        // save used to fail the whole upload — partner saw “some items sync,
        // others miss”. Photo is best-effort afterward.
        let photoData = item.imageData
        try await saveOverwriting(record)
        if let data = photoData, !data.isEmpty {
            do {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(item.id.uuidString).jpg")
                try data.write(to: url)
                record["image"] = CKAsset(fileURL: url)
                try await saveOverwriting(record)
            } catch {
                // Item row is already shared; photo can retry on next Force sync.
            }
        }
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
        // Clear list fields with empty/zero values — do not nil-delete keys
        // (nil deletes can trigger invalidArguments on Production).
        record["title"] = ""
        record["urlString"] = ""
        record["notes"] = ""
        record["categoryRaw"] = ""
        record["chrisHearted"] = 0
        record["deenaHearted"] = 0
        record["isDone"] = 0
        record["notifyKind"] = ""
        let extraURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id.uuidString)-\(fileSuffix).jpg")
        guard (try? extra.write(to: extraURL)) != nil else { return }
        record["image"] = CKAsset(fileURL: extraURL)
        try? await saveOverwriting(record)
    }

    private func applyExtraPhoto(_ record: CKRecord, to item: TodoItem) {
        if let asset = record["image"] as? CKAsset, let url = asset.fileURL,
           let data = try? Data(contentsOf: url), !data.isEmpty, data.count < 8_000_000 {
            let remoteUpdated = record["updatedAt"] as? Date
                ?? record.modificationDate
                ?? .distantPast
            let localUpdated = item.updatedAt ?? item.createdAt
            // Never clobber a newer local bottom photo with a stale companion.
            let remoteMayOverwrite = remoteUpdated > localUpdated
            switch RemoteItemApply.extraSlot(recordName: record.recordID.recordName) {
            case 3:
                if item.extraImageData3 == nil || remoteMayOverwrite {
                    item.extraImageData3 = data
                }
            case 2:
                if item.extraImageData2 == nil || remoteMayOverwrite {
                    item.extraImageData2 = data
                }
            default:
                if item.extraImageData == nil || remoteMayOverwrite {
                    item.extraImageData = data
                }
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
        // Legacy image2 on the item record is superseded by companion extra-*
        // rows. Only fill an empty slot so a stale image2 cannot replace a
        // photo the user just added (looked like "deleted + duplicate").
        if item.extraImageData == nil,
           let asset = record["image2"] as? CKAsset, let url = asset.fileURL,
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

    /// Read-modify-write the shared pair record with optimistic concurrency so a
    /// simultaneous update from the partner device cannot clobber our change
    /// (which used to drop freshly-added item IDs from the catalog and make new
    /// entries disappear). `mutate` returns true when it changed the record.
    private func mutatePairRecord(_ mutate: @escaping (CKRecord) -> Bool) async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        let recordID = CKRecord.ID(recordName: "pair-\(pairID)")
        var attempt = 0
        while true {
            let record = try await database.record(for: recordID)
            guard mutate(record) else { return }
            do {
                let outcome = try await database.modifyRecords(
                    saving: [record],
                    deleting: [],
                    savePolicy: .ifServerRecordUnchanged
                )
                if case .failure(let error)? = outcome.saveResults[record.recordID] {
                    throw error
                }
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 5 {
                attempt += 1
                continue
            }
        }
    }

    private func registerItemIDs(_ itemIDs: [String], retries: Int = 1) async throws {
        let blocked = Set(DeletedItemLedger.ids(pairID: PairSession.shared.pairID))
        let allowed = itemIDs.filter { !blocked.contains($0) && CloudKitValues.markedDeletedID($0) == nil }
        guard !allowed.isEmpty else { return }
        // Rethrow so upload can surface catalog failures. Callers that must not
        // fail (heal / reorder) use try?. Pull still accepts push-hint and
        // provisional uncatalogued adds when this write races or is rejected.
        var attempt = 0
        var lastError: Error?
        let maxAttempts = max(1, retries)
        while attempt < maxAttempts {
            do {
                try await mutatePairRecord { record in
                    let merged = CloudKitValues.mergedItemIDs(record["itemIDs"] as? String, allowed)
                    guard merged != (record["itemIDs"] as? String ?? "") else { return false }
                    record["itemIDs"] = merged
                    return true
                }
                return
            } catch {
                lastError = error
                attempt += 1
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(250_000_000 * attempt))
                }
            }
        }
        if let lastError { throw lastError }
    }

    /// Remember a delete inside `itemIDs` (`x:<uuid>`), which Production CloudKit
    /// already accepts. Saved apart from `deletedIDs` so a schema rejection of
    /// that newer field cannot roll back the mark.
    private func markCatalogDeleted(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await mutatePairRecord { record in
            let updated = CloudKitValues.markDeleted(record["itemIDs"] as? String, ids: ids)
            guard updated != (record["itemIDs"] as? String ?? "") else { return false }
            record["itemIDs"] = updated
            return true
        }
    }

    /// Drop local rows this phone already deleted, including a copy of the same
    /// YouTube link that came back under a new id.
    private func dropLedgerMatches(in modelContext: ModelContext, pairID: String?) {
        guard let pairID, !pairID.isEmpty else { return }
        var didDelete = false
        for item in ItemStore.items(forPair: pairID, in: modelContext) {
            let idHit = DeletedItemLedger.contains(pairID: pairID, id: item.id.uuidString)
            let urlHit = DeletedItemLedger.containsURL(pairID: pairID, urlString: item.urlString)
            guard idHit || urlHit else { continue }
            if urlHit {
                DeletedItemLedger.record(pairID: pairID, id: item.id, urlString: item.urlString)
            }
            modelContext.delete(item)
            didDelete = true
        }
        if didDelete {
            try? modelContext.save()
        }
    }

    private func subscribe() async throws {
        guard let pairID = PairSession.shared.pairID,
              let myRole = PairSession.shared.role else { return }
        let partnerRole = myRole == .chris ? PairRole.deena.rawValue : PairRole.chris.rawValue
        let prefix = pairID.prefix(8)
        // v6: alert only for partner edits — v5's last-resort pairID predicate
        // made BOTH phones banner on every local save.
        let alertID = "todo42-alert-v6-\(prefix)-\(myRole.rawValue)"
        let silentID = "todo42-silent-v6-\(prefix)-\(myRole.rawValue)"

        let migrateKey = "todo42.pushSub.v6.\(prefix)"
        if !UserDefaults.standard.bool(forKey: migrateKey) {
            for oldID in [
                "todo42-tditem-\(prefix)",
                "todo42-tditem-all",
                "todo42-alert-\(prefix)-\(myRole.rawValue)",
                "todo42-alert-v4-\(prefix)-\(myRole.rawValue)",
                "todo42-silent-v4-\(prefix)-\(myRole.rawValue)",
                "todo42-alert-v5-\(prefix)-\(myRole.rawValue)",
                "todo42-silent-v5-\(prefix)-\(myRole.rawValue)",
            ] {
                try? await database.deleteSubscription(withID: oldID)
            }
            UserDefaults.standard.set(true, forKey: migrateKey)
        }

        let silentInfo = CKSubscription.NotificationInfo()
        silentInfo.shouldSendContentAvailable = true
        silentInfo.shouldBadge = false
        // Silent wake on any pair change (for pull). No lock-screen banner.
        let silent = CKQuerySubscription(
            recordType: "TDItem",
            predicate: NSPredicate(format: "pairID == %@", pairID),
            subscriptionID: silentID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        silent.notificationInfo = silentInfo
        do {
            _ = try await database.save(silent)
        } catch {
            try? await database.deleteSubscription(withID: silentID)
            try? await database.save(silent)
        }

        // Visible banners: partner edits only. Never fall back to pairID-only —
        // that notified the sender too.
        let notifyKinds = ["add", "heart", "edit", "reorder", "delete"]
        let predicates = [
            NSPredicate(format: "pairID == %@ AND lastEditor == %@ AND notifyKind IN %@", pairID, partnerRole, notifyKinds),
            NSPredicate(format: "pairID == %@ AND lastEditor == %@", pairID, partnerRole),
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
                try? await database.deleteSubscription(withID: alertID)
                if let _ = try? await database.save(subscription) {
                    return
                }
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
