import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class CategoryNames {
    static let shared = CategoryNames()
    static let storageKey = "todo42.categoryTitles"
    static let updatedAtKey = "todo42.categoryTitlesUpdatedAt"
    static let cloudField = "categoryTitlesJSON"

    private let defaults: UserDefaults
    private var titles: [String: String]
    private var updatedAt: Date
    private var uploadTask: Task<Void, Never>?

    private struct CloudPayload: Codable {
        var updatedAt: TimeInterval
        var titles: [String: String]
    }

    private init() {
        defaults = UserDefaults(suiteName: AppGroup.id) ?? .standard
        titles = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        let stamp = defaults.double(forKey: Self.updatedAtKey)
        updatedAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : .distantPast
        migrateLegacyTripTitleIfNeeded()
    }

    /// Old single Trip tab renames (e.g. to "Vegas Trip 4 Two") lived under "trip".
    /// Move those onto the matching trip tab so Projects keeps its own name.
    private func migrateLegacyTripTitleIfNeeded() {
        guard let tripTitle = titles["trip"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tripTitle.isEmpty else { return }
        let lower = tripTitle.lowercased()
        if titles["vegasTrip"] == nil,
           lower.contains("vegas") || tripTitle == "Vegas Trip 4 Two" {
            titles["vegasTrip"] = tripTitle
        } else if titles["londonTrip"] == nil, lower.contains("london") {
            titles["londonTrip"] = tripTitle
        } else if titles["dcTrip"] == nil,
                  lower.contains("dc") || lower.contains("washington") {
            titles["dcTrip"] = tripTitle
        }
        titles.removeValue(forKey: "trip")
        // Drop a mistaken Projects override that copied the old Trip label.
        if let projects = titles["projects"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           projects.compare("Vegas Trip 4 Two", options: .caseInsensitive) == .orderedSame
            || projects.compare("Trip 4 Two", options: .caseInsensitive) == .orderedSame {
            titles.removeValue(forKey: "projects")
        }
        persist()
    }

    func title(for category: ItemCategory) -> String {
        let custom = titles[category.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        return category.defaultTitle
    }

    func binding(for category: ItemCategory) -> Binding<String> {
        Binding(
            get: { self.title(for: category) },
            set: { self.setTitle($0, for: category) }
        )
    }

    func setTitle(_ raw: String, for category: ItemCategory) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = titles
        if trimmed.isEmpty || trimmed == category.defaultTitle {
            next.removeValue(forKey: category.rawValue)
        } else {
            next[category.rawValue] = trimmed
        }
        titles = next
        updatedAt = Date()
        persist()
        scheduleUpload()
    }

    func payloadJSON() -> String {
        let payload = CloudPayload(
            updatedAt: max(updatedAt.timeIntervalSince1970, 0),
            titles: Dictionary(uniqueKeysWithValues: ItemCategory.allCases.map { ($0.rawValue, title(for: $0)) })
        )
        guard let data = try? JSONEncoder().encode(payload),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    func applyRemoteJSON(_ raw: String?) {
        guard let raw, let data = raw.data(using: .utf8),
              let payload = try? JSONDecoder().decode(CloudPayload.self, from: data) else { return }
        if payload.updatedAt <= updatedAt.timeIntervalSince1970 { return }
        var next: [String: String] = [:]
        for category in ItemCategory.allCases {
            let value = payload.titles[category.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty, value != category.defaultTitle {
                next[category.rawValue] = value
            }
        }
        titles = next
        updatedAt = Date(timeIntervalSince1970: payload.updatedAt)
        persist()
    }

    func flushUpload() {
        uploadTask?.cancel()
        uploadTask = nil
        guard PairSession.shared.isPaired else { return }
        Task { await CloudSync.shared.uploadCategoryTitles() }
    }

    private func persist() {
        defaults.set(titles, forKey: Self.storageKey)
        defaults.set(updatedAt.timeIntervalSince1970, forKey: Self.updatedAtKey)
    }

    private func scheduleUpload() {
        uploadTask?.cancel()
        uploadTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            guard PairSession.shared.isPaired else { return }
            await CloudSync.shared.uploadCategoryTitles()
        }
    }
}
