import Foundation
import UIKit

/// Local-only profile heads for pair UI (not synced to iCloud).
enum PairHeadPhotos {
    enum Slot: String {
        case me
        case partner
    }

    static func pairKey(for pairID: String?) -> String {
        guard let pairID, !pairID.isEmpty else { return "draft" }
        return pairID
    }

    static func load(pairKey: String, slot: Slot) -> Data? {
        guard let url = fileURL(pairKey: pairKey, slot: slot),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func image(pairKey: String, slot: Slot) -> UIImage? {
        guard let data = load(pairKey: pairKey, slot: slot) else { return nil }
        return UIImage(data: data)
    }

    static func save(pairKey: String, slot: Slot, data: Data?) {
        guard let url = fileURL(pairKey: pairKey, slot: slot) else { return }
        if let data, !data.isEmpty {
            try? ensureDirectory()
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Move draft heads onto a real pair after invite/join.
    static func promoteDraft(to pairID: String) {
        guard pairID != "draft", !pairID.isEmpty else { return }
        for slot in [Slot.me, Slot.partner] {
            guard let data = load(pairKey: "draft", slot: slot) else { continue }
            if load(pairKey: pairID, slot: slot) == nil {
                save(pairKey: pairID, slot: slot, data: data)
            }
            save(pairKey: "draft", slot: slot, data: nil)
        }
    }

    static func compressedHead(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 512
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.jpegData(compressionQuality: 0.85)
    }

    private static func fileURL(pairKey: String, slot: Slot) -> URL? {
        directoryURL()?.appendingPathComponent("\(pairKey)-\(slot.rawValue).jpg")
    }

    private static func directoryURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PairHeads", isDirectory: true)
    }

    private static func ensureDirectory() throws {
        guard let dir = directoryURL() else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
