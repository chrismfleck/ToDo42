import SwiftUI
import WebKit

enum IdeaSource: String, CaseIterable, Identifiable {
    case airbnb
    case google
    case maps
    case instagram
    case tiktok
    case tripadvisor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .airbnb: "Airbnb"
        case .google: "Google"
        case .maps: "Maps"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .tripadvisor: "TripAdvisor"
        }
    }

    var symbol: String {
        switch self {
        case .airbnb: "bed.double"
        case .google: "globe"
        case .maps: "map"
        case .instagram: "camera"
        case .tiktok: "play.rectangle"
        case .tripadvisor: "binoculars"
        }
    }

    var opensInAppBrowser: Bool {
        switch self {
        case .instagram, .tiktok: false
        default: true
        }
    }

    func searchURL(keywords: String) -> URL? {
        let query = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let string: String
        switch self {
        case .airbnb:
            string = query.isEmpty
                ? "https://www.airbnb.com/"
                : "https://www.airbnb.com/s/homes?query=\(encoded)"
        case .google:
            string = query.isEmpty
                ? "https://www.google.com/"
                : "https://www.google.com/search?q=\(encoded)"
        case .maps:
            string = query.isEmpty
                ? "https://maps.apple.com/"
                : "https://maps.apple.com/?q=\(encoded)"
        case .instagram:
            string = query.isEmpty
                ? "https://www.instagram.com/"
                : "https://www.instagram.com/explore/search/keyword/?q=\(encoded)"
        case .tiktok:
            string = query.isEmpty
                ? "https://www.tiktok.com/"
                : "https://www.tiktok.com/search?q=\(encoded)"
        case .tripadvisor:
            string = query.isEmpty
                ? "https://www.tripadvisor.com/"
                : "https://www.tripadvisor.com/Search?q=\(encoded)"
        }
        return URL(string: string)
    }

    /// Native app links that keep the keywords. Instagram has no official
    /// full-text search scheme, so we open the hashtag for the first word.
    func nativeSearchURLs(keywords: String) -> [URL] {
        let query = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let tags = Self.hashtagSlugs(query)
        switch self {
        case .instagram:
            if query.isEmpty {
                return [URL(string: "instagram://app")].compactMap { $0 }
            }
            return tags.compactMap { URL(string: "instagram://tag?name=\($0)") }
        case .tiktok:
            if query.isEmpty {
                return [URL(string: "tiktok://"), URL(string: "snssdk1233://")].compactMap { $0 }
            }
            var urls = [
                URL(string: "snssdk1233://search?keyword=\(encoded)"),
                URL(string: "tiktok://search?keyword=\(encoded)"),
                URL(string: "aweme://search?keyword=\(encoded)"),
            ]
            urls += tags.map { URL(string: "tiktok://hashtag/\($0)") }
            return urls.compactMap { $0 }
        default:
            return []
        }
    }

    static func hashtagSlugs(_ keywords: String) -> [String] {
        let folded = keywords.folding(options: .diacriticInsensitive, locale: .current)
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { String($0).lowercased() }
        var slugs: [String] = []
        if let first = words.first, !first.isEmpty {
            slugs.append(first)
        }
        let joined = words.joined()
        if !joined.isEmpty, !slugs.contains(joined) {
            slugs.append(joined)
        }
        return slugs
    }
}

private struct BrowserPage: Identifiable {
    let id = UUID()
    let url: URL
}

struct FindIdeasView: View {
    var onSavePage: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keywords = ""
    @State private var browser: BrowserPage?

    var body: some View {
        Form {
            Section {
                TextField("Asheville cabin hot tub", text: $keywords)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Keywords")
            } footer: {
                Text("Type a few words, then pick where to look.")
            }

            Section {
                ForEach(IdeaSource.allCases) { source in
                    Button {
                        open(source)
                    } label: {
                        Label(source.title, systemImage: source.symbol)
                    }
                }
            } header: {
                Text("Look in")
            } footer: {
                Text("Airbnb, Google, Maps, and TripAdvisor open here. Instagram and TikTok open those apps to search.")
            }
        }
        .navigationTitle("Find Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $browser) { page in
            FindIdeasBrowserSheet(
                startURL: page.url,
                onSave: { pageURL in
                    onSavePage(pageURL)
                    browser = nil
                    Task { @MainActor in
                        dismiss()
                    }
                },
                onDone: {
                    browser = nil
                }
            )
        }
    }

    private func open(_ source: IdeaSource) {
        guard let url = source.searchURL(keywords: keywords) else { return }
        if source.opensInAppBrowser {
            browser = BrowserPage(url: url)
            return
        }
        let query = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        let natives = source.nativeSearchURLs(keywords: query).filter { UIApplication.shared.canOpenURL($0) }

        // Prefer a native search/hashtag link so keywords are not dropped.
        if !query.isEmpty, let native = natives.first {
            UIApplication.shared.open(native)
            return
        }

        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { success in
            if success { return }
            if let native = natives.first {
                UIApplication.shared.open(native)
                return
            }
            UIApplication.shared.open(url)
        }
    }
}

private struct FindIdeasBrowserSheet: View {
    let startURL: URL
    var onSave: (String) -> Void
    var onDone: () -> Void

    @State private var currentURL: URL?
    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var goBackToken = 0
    @State private var goForwardToken = 0

    var body: some View {
        NavigationStack {
            FindIdeasWebView(
                startURL: startURL,
                currentURL: $currentURL,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                goBackToken: goBackToken,
                goForwardToken: goForwardToken
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(currentURL?.host ?? "Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        goBackToken += 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!canGoBack)
                    Button {
                        goForwardToken += 1
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canGoForward)
                    Spacer()
                    if isLoading {
                        ProgressView()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save 4 Two") {
                        if let page = currentURL?.absoluteString {
                            onSave(page)
                        }
                    }
                    .disabled(currentURL == nil)
                }
            }
        }
    }
}

private struct FindIdeasWebView: UIViewRepresentable {
    let startURL: URL
    @Binding var currentURL: URL?
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    var goBackToken: Int
    var goForwardToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
        web.addObserver(context.coordinator, forKeyPath: "URL", options: .new, context: nil)
        web.addObserver(context.coordinator, forKeyPath: "loading", options: .new, context: nil)
        web.addObserver(context.coordinator, forKeyPath: "canGoBack", options: .new, context: nil)
        web.addObserver(context.coordinator, forKeyPath: "canGoForward", options: .new, context: nil)
        web.load(URLRequest(url: startURL))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if goBackToken != context.coordinator.lastGoBackToken {
            context.coordinator.lastGoBackToken = goBackToken
            if web.canGoBack { web.goBack() }
        }
        if goForwardToken != context.coordinator.lastGoForwardToken {
            context.coordinator.lastGoForwardToken = goForwardToken
            if web.canGoForward { web.goForward() }
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.removeObserver(coordinator, forKeyPath: "URL")
        web.removeObserver(coordinator, forKeyPath: "loading")
        web.removeObserver(coordinator, forKeyPath: "canGoBack")
        web.removeObserver(coordinator, forKeyPath: "canGoForward")
        web.navigationDelegate = nil
        web.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: FindIdeasWebView
        var lastGoBackToken = 0
        var lastGoForwardToken = 0

        init(_ parent: FindIdeasWebView) {
            self.parent = parent
        }

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            guard let web = object as? WKWebView else { return }
            DispatchQueue.main.async {
                self.parent.currentURL = web.url
                self.parent.isLoading = web.isLoading
                self.parent.canGoBack = web.canGoBack
                self.parent.canGoForward = web.canGoForward
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
               scheme != "http", scheme != "https", scheme != "about" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
