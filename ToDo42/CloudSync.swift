import Foundation
import Observation
import SwiftData
import CloudKit
import UIKit
import UserNotifications

enum PairRole: String {
    case chris
    case deena

    var displayName: String { rawValue.capitalized }
    var partnerName: String { self == .chris ? "Deena" : "Chris" }
}

@Observable
@MainActor
final class PairSession {
    static let shared = PairSession()

    var pairID: String?
    var role: PairRole?
    var inviteCode: String?
    var statusMessage = ""
    var isBusy = false

    private let defaults = UserDefaults.standard
    private let pairKey = "todo42.pairID"
    private let roleKey = "todo42.pairRole"
    private let codeKey = "todo42.inviteCode"

    var isPaired: Bool { pairID != nil && role != nil }
    var isApplyingRemote = false

    private init() {
        pairID = defaults.string(forKey: pairKey)
        if let raw = defaults.string(forKey: roleKey) {
            role = PairRole(rawValue: raw)
        }
        inviteCode = defaults.string(forKey: codeKey)
    }

    func persist() {
        defaults.set(pairID, forKey: pairKey)
        defaults.set(role?.rawValue, forKey: roleKey)
        defaults.set(inviteCode, forKey: codeKey)
    }

    func noteLocalEdit(_ item: TodoItem, kind: String) {
        guard !isApplyingRemote else { return }
        item.updatedAt = .now
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

        _ = try await database.modifyRecords(saving: [codeRecord, pairRecord], deleting: [])

        let session = PairSession.shared
        session.pairID = pairID
        session.role = .chris
        session.inviteCode = code
        session.persist()
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
        session.persist()
        try await subscribe()
        try await requestNotifications()
    }

    func sync(modelContext: ModelContext, items: [TodoItem]) async {
        guard PairSession.shared.isPaired else { return }
        do {
            try await ensureiCloud()
            try await pull(modelContext: modelContext, items: items)
            try await pushAll(items)
        } catch {
            PairSession.shared.statusMessage = error.localizedDescription
        }
    }

    func upload(_ item: TodoItem, notifyKind: String) async {
        guard PairSession.shared.isPaired else { return }
        do {
            try await saveItem(item, notifyKind: notifyKind)
            try await registerItemID(item.id.uuidString)
        } catch {
            PairSession.shared.statusMessage = error.localizedDescription
        }
    }

    func deleteRemote(_ id: UUID) async {
        guard PairSession.shared.isPaired else { return }
        try? await database.deleteRecord(withID: CKRecord.ID(recordName: "item-\(id.uuidString)"))
        try? await removeItemID(id.uuidString)
    }

    func handleRemoteNotification(modelContext: ModelContext, items: [TodoItem]) async {
        await sync(modelContext: modelContext, items: items)
    }

    func inviteText(code: String) -> String {
        """
        Join me on ToDo 4 2.

        1. I’ll send you the TestFlight install link from App Store Connect.
        2. After the app is on your iPhone, open it and tap the two-person icon.
        3. Choose “I have a code” and enter: \(code)

        Stay signed in to iCloud on your iPhone so our lists can sync.
        """
    }

    private func pull(modelContext: ModelContext, items: [TodoItem]) async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        let pair = try await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
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
                if remoteUpdated > local.updatedAt {
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
            try await registerItemID(item.id.uuidString)
        }
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
        record["updatedAt"] = item.updatedAt
        record["lastEditor"] = item.lastEditor
        if !notifyKind.isEmpty {
            record["notifyKind"] = notifyKind
        }
        if let data = item.imageData, !data.isEmpty {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id.uuidString).jpg")
            try data.write(to: url)
            record["image"] = CKAsset(fileURL: url)
        }
        _ = try await database.save(record)
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

    private func registerItemID(_ itemID: String) async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        let record = try await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
        var ids = (record["itemIDs"] as? String ?? "").split(separator: ",").map(String.init)
        if !ids.contains(itemID) {
            ids.append(itemID)
            record["itemIDs"] = ids.joined(separator: ",")
            _ = try await database.save(record)
        }
    }

    private func removeItemID(_ itemID: String) async throws {
        guard let pairID = PairSession.shared.pairID else { return }
        let record = try await database.record(for: CKRecord.ID(recordName: "pair-\(pairID)"))
        let ids = (record["itemIDs"] as? String ?? "").split(separator: ",").map(String.init).filter { $0 != itemID }
        record["itemIDs"] = ids.joined(separator: ",")
        _ = try await database.save(record)
    }

    private func subscribe() async throws {
        let id = "todo42-items"
        let subscription = CKDatabaseSubscription(subscriptionID: id)
        subscription.recordType = "TDItem"
        let info = CKNotificationInfo()
        info.shouldSendContentAvailable = true
        info.shouldBadge = false
        subscription.notificationInfo = info
        _ = try? await database.save(subscription)
    }

    private func requestNotifications() async throws {
        let center = UNUserNotificationCenter.current()
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        await UIApplication.shared.registerForRemoteNotifications()
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
        let who = editor.capitalized
        let title = record["title"] as? String ?? "an item"
        postNotice(title: "\(who) added an item", body: title)
    }

    private func notifyUpdate(_ record: CKRecord, heartChanged: Bool) {
        let editor = record["lastEditor"] as? String ?? ""
        guard editor != PairSession.shared.role?.rawValue else { return }
        let who = editor.capitalized
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
