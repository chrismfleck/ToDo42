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

    func persist() {
        persistLocal()
        if isPaired {
            Task { await CloudSync.shared.uploadPairNames() }
        }
    }

    func persistLocal() {
        defaults.set(pairID, forKey: pairKey)
        defaults.set(role?.rawValue, forKey: roleKey)
        defaults.set(inviteCode, forKey: codeKey)
        defaults.set(myName, forKey: myNameKey)
        defaults.set(partnerName, forKey: partnerNameKey)
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
        let record = try await database.record(for: CKRecord.ID(recordName: "code-\(trimmed)"))
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

    func sync(modelContext: ModelContext, items: [TodoItem]) async {
        guard PairSession.shared.isPaired else { return }
        await enqueue {
            do {
                try await self.ensureiCloud()
                try await self.pull(modelContext: modelContext, items: items)
                try await self.pushAll(items)
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
                try await self.registerItemIDs([item.id.uuidString])
                PairSession.shared.statusMessage = ""
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
                try await self.removeItemID(id.uuidString)
                PairSession.shared.statusMessage = ""
            } catch {
                PairSession.shared.statusMessage = Self.friendlyMessage(error)
            }
        }
    }

    func handleRemoteNotification(modelContext: ModelContext, items: [TodoItem]) async {
        await sync(modelContext: modelContext, items: items)
    }

    func inviteText(code: String) -> String {
        """
        Join \(PairSession.shared.trimmedMyName.isEmpty ? "me" : PairSession.shared.trimmedMyName) on Save4Two.

        1. I’ll send you the TestFlight install link from App Store Connect.
        2. After the app is on your iPhone, open it and tap the two-person icon.
        3. Choose “I have a code” and enter: \(code)

        Stay signed in to iCloud on your iPhone so our lists can sync.
        """
    }

    private func pull(modelContext: ModelContext, items: [TodoItem]) async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        let pair = try await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
        PairSession.shared.applyRemoteNames(
            host: pair["hostName"] as? String,
            guest: pair["guestName"] as? String
        )
        let idList = (pair["itemIDs"] as? String ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !idList.isEmpty else { return }

        let recordIDs = idList.map { CKRecord.ID(recordName: "item-\($0)") }
        let result = try await database.records(for: recordIDs)
        var remote: [CKRecord] = []
        for id in recordIDs {
            if let record = try? result[id]?.get() {
                remote.append(record)
            }
        }

        let session = PairSession.shared
        session.isApplyingRemote = true
        defer { session.isApplyingRemote = false }

        let localByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, $0) })
        for record in remote {
            guard let itemID = record["itemID"] as? String, let uuid = UUID(uuidString: itemID) else { continue }
            let remoteUpdated = record["updatedAt"] as? Date ?? .distantPast
            if let local = localByID[itemID] {
                if remoteUpdated > (local.updatedAt ?? local.createdAt) {
                    let heartChanged = local.chrisHearted != ((record["chrisHearted"] as? Int) == 1)
                        || local.deenaHearted != ((record["deenaHearted"] as? Int) == 1)
                    apply(record, to: local)
                    notifyUpdate(record, heartChanged: heartChanged)
                }
            } else {
                let item = TodoItem(
                    title: record["title"] as? String ?? "Untitled",
                    category: ItemCategory(rawValue: record["categoryRaw"] as? String ?? "places") ?? .places,
                    urlString: record["urlString"] as? String,
                    notes: record["notes"] as? String ?? "",
                    sortOrder: record["sortOrder"] as? Int ?? 0
                )
                item.id = uuid
                apply(record, to: item)
                modelContext.insert(item)
                notifyNew(record)
            }
        }
    }

    private func pushAll(_ items: [TodoItem]) async throws {
        for item in items {
            try await saveItem(item, notifyKind: "")
        }
        try await registerItemIDs(items.map(\.id.uuidString))
    }

    private func saveItem(_ item: TodoItem, notifyKind: String) async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        let recordID = CKRecord.ID(recordName: "item-\(item.id.uuidString)")
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: "TDItem", recordID: recordID)
        }
        record["itemID"] = item.id.uuidString
        record["pairID"] = pairID
        record["title"] = item.title
        record["urlString"] = item.urlString ?? ""
        record["notes"] = item.notes
        record["categoryRaw"] = item.categoryRaw
        record["chrisHearted"] = item.chrisHearted ? 1 : 0
        record["deenaHearted"] = item.deenaHearted ? 1 : 0
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
    }

    private func apply(_ record: CKRecord, to item: TodoItem) {
        item.title = record["title"] as? String ?? item.title
        let url = record["urlString"] as? String ?? ""
        item.urlString = url.isEmpty ? nil : url
        item.notes = record["notes"] as? String ?? item.notes
        item.categoryRaw = record["categoryRaw"] as? String ?? item.categoryRaw
        item.chrisHearted = (record["chrisHearted"] as? Int) == 1
        item.deenaHearted = (record["deenaHearted"] as? Int) == 1
        item.isDone = (record["isDone"] as? Int) == 1
        item.sortOrder = record["sortOrder"] as? Int ?? item.sortOrder
        item.createdAt = record["createdAt"] as? Date ?? item.createdAt
        item.updatedAt = record["updatedAt"] as? Date ?? item.updatedAt
        item.lastEditor = record["lastEditor"] as? String ?? item.lastEditor
        if let asset = record["image"] as? CKAsset, let url = asset.fileURL,
           let data = try? Data(contentsOf: url) {
            item.imageData = data
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
        try await saveOverwriting(record)
    }

    private func removeItemID(_ itemID: String) async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        let record = try await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
        let ids = (record["itemIDs"] as? String ?? "").split(separator: ",").map(String.init).filter { $0 != itemID && !$0.isEmpty }
        record["itemIDs"] = ids.joined(separator: ",")
        try await saveOverwriting(record)
    }

    private func subscribe() async throws {
        let id = "todo42-items"
        let subscription = CKDatabaseSubscription(subscriptionID: id)
        subscription.recordType = "TDItem"
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.shouldBadge = false
        subscription.notificationInfo = info
        do {
            _ = try await database.save(subscription)
        } catch {
            // Already subscribed on this device.
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
        let editor = record["lastEditor"] as? String ?? ""
        guard editor != PairSession.shared.role?.rawValue else { return }
        let who = PairSession.shared.displayName(forEditor: editor)
        let title = record["title"] as? String ?? "an item"
        if heartChanged {
            postNotice(title: "\(who) hearted an item", body: title)
        } else {
            postNotice(title: "\(who) updated an item", body: title)
        }
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
