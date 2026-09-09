import AVFoundation
import UniformTypeIdentifiers
import UIKit

enum ShareMedia {
    static func image(from provider: NSItemProvider) async -> UIImage? {
        if provider.canLoadObject(ofClass: UIImage.self) {
            let loaded: UIImage? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
            if let loaded { return loaded }
        }

        let typeIDs = provider.registeredTypeIdentifiers
        let imageTypes = typeIDs.filter { id in
            id == UTType.image.identifier
                || id == UTType.jpeg.identifier
                || id == UTType.png.identifier
                || id == UTType.heic.identifier
                || id == UTType.webP.identifier
                || UTType(id)?.conforms(to: .image) == true
        }
        for typeID in imageTypes + [UTType.image.identifier] {
            if let image = await loadImageRepresentation(provider, type: typeID) {
                return image
            }
        }

        let movieTypes = typeIDs.filter { id in
            id == UTType.movie.identifier
                || id == UTType.mpeg4Movie.identifier
                || id == UTType.quickTimeMovie.identifier
                || id == "com.apple.quicktime-movie"
                || id == "public.mpeg-4"
                || UTType(id)?.conforms(to: .movie) == true
        }
        for typeID in movieTypes + [UTType.movie.identifier] {
            if let image = await loadMovieThumbnail(provider, type: typeID) {
                return image
            }
        }
        return nil
    }

    static func image(fromFileURL url: URL) -> UIImage? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            return image
        }
        return thumbnail(fromMovieURL: url)
    }

    static func jpegData(from image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        let size: CGSize
        if longest > maxSide, longest > 0 {
            let scale = maxSide / longest
            size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        } else if image.size.width > 0, image.size.height > 0 {
            size = image.size
        } else {
            size = CGSize(width: 1, height: 1)
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }

    private static func loadImageRepresentation(_ provider: NSItemProvider, type: String) async -> UIImage? {
        if let data = await loadData(provider, type: type), let image = UIImage(data: data) {
            return image
        }
        if let fileURL = await loadFile(provider, type: type), let image = image(fromFileURL: fileURL) {
            return image
        }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                continuation.resume(returning: image(fromItem: item))
            }
        }
    }

    private static func loadMovieThumbnail(_ provider: NSItemProvider, type: String) async -> UIImage? {
        if let fileURL = await loadFile(provider, type: type), let image = thumbnail(fromMovieURL: fileURL) {
            return image
        }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: thumbnail(fromMovieURL: url))
                } else if let data = item as? Data {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
                    try? data.write(to: tmp)
                    continuation.resume(returning: thumbnail(fromMovieURL: tmp))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func image(fromItem item: Any?) -> UIImage? {
        if let image = item as? UIImage { return image }
        if let data = item as? Data { return UIImage(data: data) }
        if let url = item as? URL { return image(fromFileURL: url) }
        return nil
    }

    private static func loadData(_ provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadFile(_ provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
                try? FileManager.default.removeItem(at: dest)
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func thumbnail(fromMovieURL url: URL) -> UIImage? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        let time = CMTime(seconds: 0.15, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
