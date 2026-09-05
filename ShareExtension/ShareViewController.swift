import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { await presentShareForm() }
    }

    private func presentShareForm() async {
        let extracted = await SharedContent.extract(from: extensionContext)

        let root = ShareFormView(
            title: extracted.title,
            urlString: extracted.urlString,
            notes: extracted.notes,
            image: extracted.image,
            pageImageURL: extracted.pageImageURL,
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            },
            onSave: { [weak self] payload, image in
                do {
                    try ShareInbox.save(payload: payload, image: image)
                    self?.extensionContext?.completeRequest(returningItems: nil)
                } catch {
                    self?.extensionContext?.cancelRequest(withError: error)
                }
            }
        )

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

private struct ExtractedShare {
    var title = ""
    var urlString = ""
    var notes = ""
    var image: UIImage?
    var pageImageURL = ""
}

private struct PageShareMeta {
    var url = ""
    var title = ""
    var description = ""
    var imageURL = ""
}

private enum SharedContent {
    static func extract(from context: NSExtensionContext?) async -> ExtractedShare {
        var result = ExtractedShare()
        guard let items = context?.inputItems as? [NSExtensionItem] else { return result }

        for item in items {
            if let title = item.attributedTitle?.string, result.title.isEmpty {
                result.title = title
            }
            if let text = item.attributedContentText?.string {
                apply(text, to: &result)
            }
            for provider in item.attachments ?? [] {
                if result.image == nil {
                    result.image = await ShareMedia.image(from: provider)
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                    apply(await loadPropertyList(provider), to: &result)
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(provider) {
                        apply(url, to: &result)
                    }
                }
                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    if let url = await loadTypedURL(provider, type: "public.file-url") {
                        apply(url, to: &result)
                    }
                }
                if result.urlString.isEmpty, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadText(provider) {
                        apply(text, to: &result)
                    }
                }
            }
        }

        if result.image == nil, !result.pageImageURL.isEmpty {
            result.image = await PageMetadata.downloadImageURL(
                result.pageImageURL,
                referer: URL(string: result.urlString)
            )
        }
        if result.title.isEmpty {
            if !result.urlString.isEmpty, let url = URL(string: result.urlString) {
                result.title = prettyTitle(from: url)
            } else {
                result.title = "Shared item"
            }
        }
        if InstagramShareText.isInstagramURL(result.urlString) {
            let split = InstagramShareText.refine(title: result.title, notes: result.notes)
            if !split.title.isEmpty { result.title = split.title }
            result.notes = split.notes
        } else if FacebookShareText.isFacebookURL(result.urlString) {
            let split = FacebookShareText.refine(title: result.title, notes: result.notes)
            if !split.title.isEmpty { result.title = split.title }
            result.notes = split.notes
        }
        let cut = SharedText.cutTitle(result.title, notes: result.notes)
        result.title = cut.title
        result.notes = cut.notes
        return result
    }

    private static func apply(_ meta: PageShareMeta, to result: inout ExtractedShare) {
        if result.urlString.isEmpty, !meta.url.isEmpty { result.urlString = meta.url }
        if result.title.isEmpty, !meta.title.isEmpty { result.title = meta.title }
        if result.notes.isEmpty, !meta.description.isEmpty { result.notes = meta.description }
        if result.pageImageURL.isEmpty, !meta.imageURL.isEmpty { result.pageImageURL = meta.imageURL }
    }

    private static func apply(_ url: URL, to result: inout ExtractedShare) {
        if url.scheme?.hasPrefix("http") == true {
            if result.urlString.isEmpty {
                result.urlString = url.absoluteString
                if result.title.isEmpty {
                    result.title = prettyTitle(from: url)
                }
            }
            return
        }
        if result.image == nil {
            result.image = ShareMedia.image(fromFileURL: url)
        }
    }

    private static func apply(_ text: String, to result: inout ExtractedShare) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
            if result.urlString.isEmpty { result.urlString = trimmed }
            return
        }
        if let detected = trimmed.split(whereSeparator: \.isWhitespace).map(String.init).first(where: { $0.hasPrefix("http") }) {
            if result.urlString.isEmpty { result.urlString = detected }
            let leftover = trimmed.replacingOccurrences(of: detected, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if result.title.isEmpty, !leftover.isEmpty { result.title = leftover }
            return
        }
        if result.title.isEmpty {
            result.title = trimmed
        } else if result.notes.isEmpty {
            result.notes = trimmed
        }
    }

    private static func prettyTitle(from url: URL) -> String {
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? ""
        if host.contains("airbnb") { return "Airbnb stay" }
        if host.contains("instagram") { return "Instagram" }
        if host.contains("tiktok") { return "TikTok" }
        if host.contains("x.com") || host.contains("twitter") { return "X post" }
        if host.contains("facebook") || host.contains("fb.com") || host.contains("fb.watch") { return "Facebook" }
        return host.isEmpty ? "Shared item" : host
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let text = item as? String, let url = URL(string: text) {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadTypedURL(_ provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let text = item as? String, let url = URL(string: text) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadPropertyList(_ provider: NSItemProvider) async -> PageShareMeta {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { item, _ in
                if let dict = item as? [String: Any] {
                    let js = dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] ?? dict
                    continuation.resume(returning: PageShareMeta(
                        url: (js["URL"] as? String) ?? (dict["URL"] as? String) ?? "",
                        title: (js["title"] as? String) ?? (dict["title"] as? String) ?? "",
                        description: (js["description"] as? String) ?? (dict["description"] as? String) ?? "",
                        imageURL: (js["imageURL"] as? String) ?? (dict["imageURL"] as? String) ?? ""
                    ))
                } else if let url = item as? URL {
                    continuation.resume(returning: PageShareMeta(url: url.absoluteString))
                } else {
                    continuation.resume(returning: PageShareMeta())
                }
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

}

struct ShareFormView: View {
    @State var title: String
    @State var urlString: String
    @State var notes: String
    @State var category: String
    @State var previewImage: UIImage?
    @State private var isLoadingMeta = false
    var pageImageURL: String
    var onCancel: () -> Void
    var onSave: (SharePayload, UIImage?) -> Void

    init(
        title: String,
        urlString: String,
        notes: String,
        image: UIImage?,
        pageImageURL: String = "",
        onCancel: @escaping () -> Void,
        onSave: @escaping (SharePayload, UIImage?) -> Void
    ) {
        _title = State(initialValue: title)
        _urlString = State(initialValue: urlString)
        _notes = State(initialValue: notes)
        _category = State(initialValue: ShareInbox.guessedCategory(urlString: urlString, title: title))
        _previewImage = State(initialValue: image)
        self.pageImageURL = pageImageURL
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipped()
                    } else if isLoadingMeta {
                        HStack {
                            Spacer()
                            ProgressView("Getting photo…")
                            Spacer()
                        }
                        .frame(height: 80)
                    }
                }
                .listRowInsets(EdgeInsets())

                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Link", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Category", selection: $category) {
                        Text("Places").tag("places")
                        Text("Fun").tag("fun")
                        Text("Eats").tag("eats")
                    }
                }
            }
            .navigationTitle("Add to Save4Two")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            SharePayload(
                                title: SharedText.normalized(title),
                                urlString: urlString.trimmingCharacters(in: .whitespacesAndNewlines),
                                notes: SharedText.reflowNotes(notes),
                                category: category
                            ),
                            previewImage
                        )
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingMeta)
                }
            }
            .task { await enrichFromPage() }
        }
    }

    private func enrichFromPage() async {
        let link = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsPhoto = previewImage == nil
        if !needsPhoto && !link.hasPrefix("http") { return }
        isLoadingMeta = needsPhoto
        if previewImage == nil, !pageImageURL.isEmpty {
            previewImage = await PageMetadata.downloadImageURL(pageImageURL, referer: URL(string: link))
        }
        guard link.hasPrefix("http") else {
            isLoadingMeta = false
            return
        }
        let meta = await PageMetadata.fetch(from: link)
        if InstagramShareText.isInstagramURL(link) {
            let split = InstagramShareText.split(from: [
                title,
                notes,
                meta.title ?? "",
                meta.description ?? "",
            ])
            if !split.title.isEmpty {
                title = split.title
                category = ShareInbox.guessedCategory(urlString: link, title: split.title + " " + split.notes)
            }
            notes = split.notes
        } else if FacebookShareText.isFacebookURL(link) {
            if PageMetadata.isPlaceholderTitle(title), let pageTitle = meta.title, !pageTitle.isEmpty {
                title = pageTitle
            }
            let split = FacebookShareText.split(from: [
                title,
                notes,
                meta.title ?? "",
                meta.description ?? "",
            ])
            if !split.title.isEmpty {
                title = split.title
                category = ShareInbox.guessedCategory(urlString: link, title: split.title + " " + split.notes)
            }
            notes = split.notes
        } else {
            if PageMetadata.isPlaceholderTitle(title), let pageTitle = meta.title, !pageTitle.isEmpty {
                title = pageTitle
                category = ShareInbox.guessedCategory(urlString: link, title: pageTitle)
            }
            if notes.isEmpty, let description = meta.description, !description.isEmpty {
                notes = description
            }
        }
        let cut = SharedText.cutTitle(title, notes: notes)
        title = cut.title
        notes = cut.notes
        if previewImage == nil {
            previewImage = meta.image
        }
        isLoadingMeta = false
    }
}
