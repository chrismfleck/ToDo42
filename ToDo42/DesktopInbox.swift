import Foundation
import Observation

/// Pending URLs sent from the Chrome/Safari S42 extension via api.save4two.com.
struct DesktopInboxItem: Identifiable, Hashable, Codable {
    var inboxID: String
    var pairID: String
    var url: String
    var title: String
    var source: String
    var status: String
    var createdAt: Double

    var id: String { inboxID }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let host = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") {
            return host
        }
        return url
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt / 1000.0)
    }
}

@Observable
@MainActor
final class DesktopInboxStore {
    static let shared = DesktopInboxStore()
    static let apiBase = URL(string: "https://api.save4two.com/v1")!

    var pending: [DesktopInboxItem] = []
    var isLoading = false
    var linkCode: String?
    var linkCodeExpiresAt: Date?
    var lastError: String = ""

    private let defaults = UserDefaults.standard
    private let phoneTokenPrefix = "todo42.desktopPhoneToken."

    var pendingCount: Int { pending.count }

    func phoneToken(for pairID: String?) -> String? {
        guard let pairID, !pairID.isEmpty else { return nil }
        return defaults.string(forKey: phoneTokenPrefix + pairID)
    }

    func setPhoneToken(_ token: String?, for pairID: String) {
        let key = phoneTokenPrefix + pairID
        if let token, !token.isEmpty {
            defaults.set(token, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Creates a 6-digit code the browser extension redeems once.
    func startDesktopLink(pairID: String, pairLabel: String) async {
        lastError = ""
        isLoading = true
        defer { isLoading = false }
        do {
            let body: [String: Any] = [
                "pairID": pairID,
                "pairLabel": pairLabel,
            ]
            let data = try await post(path: "link/start", json: body)
            let code = (data["code"] as? String) ?? ""
            let phoneToken = (data["phoneToken"] as? String) ?? ""
            let expiresIn = (data["expiresIn"] as? Int) ?? 600
            guard code.count == 6, !phoneToken.isEmpty else {
                lastError = "Couldn't create a desktop link code."
                return
            }
            setPhoneToken(phoneToken, for: pairID)
            linkCode = code
            linkCodeExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
            await refresh(pairID: pairID)
        } catch {
            lastError = friendly(error)
        }
    }

    func refresh(pairID: String?) async {
        guard let pairID, let token = phoneToken(for: pairID), !token.isEmpty else {
            pending = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            var comps = URLComponents(
                url: Self.apiBase.appendingPathComponent("inbox"),
                resolvingAgainstBaseURL: false
            )!
            comps.queryItems = [URLQueryItem(name: "phoneToken", value: token)]
            var req = URLRequest(url: comps.url!)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let rows = (decoded?["items"] as? [[String: Any]]) ?? []
            pending = rows.compactMap { Self.parseItem($0) }
            lastError = ""
        } catch {
            // Keep existing pending on transient failures.
            lastError = friendly(error)
        }
    }

    func consume(_ item: DesktopInboxItem, pairID: String?) async {
        pending.removeAll { $0.inboxID == item.inboxID }
        guard let token = phoneToken(for: pairID) else { return }
        do {
            _ = try await post(
                path: "inbox/consume",
                json: ["phoneToken": token, "inboxID": item.inboxID],
                bearer: token
            )
        } catch {
            // Row already removed locally; next refresh reconciles.
        }
    }

    private func post(path: String, json: [String: Any], bearer: String? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: Self.apiBase.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200...299).contains(http.statusCode) else {
            let message = (obj["error"] as? String) ?? "request_failed"
            throw NSError(domain: "DesktopInbox", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }
        return obj
    }

    private static func parseItem(_ row: [String: Any]) -> DesktopInboxItem? {
        guard let inboxID = row["inboxID"] as? String,
              let pairID = row["pairID"] as? String,
              let url = row["url"] as? String else { return nil }
        let created: Double
        if let n = row["createdAt"] as? Double {
            created = n
        } else if let n = row["createdAt"] as? Int {
            created = Double(n)
        } else {
            created = Date().timeIntervalSince1970 * 1000
        }
        return DesktopInboxItem(
            inboxID: inboxID,
            pairID: pairID,
            url: url,
            title: (row["title"] as? String) ?? "",
            source: (row["source"] as? String) ?? "desktop",
            status: (row["status"] as? String) ?? "pending",
            createdAt: created
        )
    }

    private func friendly(_ error: Error) -> String {
        if let urlErr = error as? URLError, urlErr.code == .notConnectedToInternet {
            return "No network."
        }
        return "Couldn't reach the desktop inbox. Try again."
    }
}
