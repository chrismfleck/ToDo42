import SwiftUI
import UIKit
import WebKit

enum IdeaSource: String, CaseIterable, Identifiable {
    case airbnb
    case google
    case maps
    case instagram
    case tiktok
    case x
    case tripadvisor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .airbnb: "Airbnb"
        case .google: "Google"
        case .maps: "Maps"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .x: "X (Twitter)"
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
        case .x: "at"
        case .tripadvisor: "binoculars"
        }
    }

    var opensInAppBrowser: Bool {
        switch self {
        case .tiktok: false
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
            if query.isEmpty {
                string = "https://www.instagram.com/"
            } else {
                // Instagram’s app only opens one tag, and its search page
                // blocks in-app browsers. Google keeps every #keyword.
                let tags = Self.hashtagQuery(query)
                let encodedTags = tags.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                string = "https://www.google.com/search?q=\(encodedTags)+site:instagram.com"
            }
        case .tiktok:
            string = query.isEmpty
                ? "https://www.tiktok.com/"
                : "https://www.tiktok.com/search?q=\(encoded)"
        case .x:
            string = query.isEmpty
                ? "https://x.com/"
                : "https://x.com/search?q=\(encoded)"
        case .tripadvisor:
            string = query.isEmpty
                ? "https://www.tripadvisor.com/"
                : "https://www.tripadvisor.com/Search?q=\(encoded)"
        }
        return URL(string: string)
    }

    /// Native app links that keep the keywords. Instagram gets every word as a #tag.
    func nativeSearchURLs(keywords: String) -> [URL] {
        let query = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let tags = Self.hashtagSlugs(query)
        switch self {
        case .instagram:
            return []
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

    static func hashtagWords(_ keywords: String) -> [String] {
        keywords
            .folding(options: .diacriticInsensitive, locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func hashtagQuery(_ keywords: String) -> String {
        hashtagWords(keywords).map { "#\($0)" }.joined(separator: " ")
    }

    static func hashtagSlugs(_ keywords: String) -> [String] {
        let words = hashtagWords(keywords)
        var slugs = words
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

/// Page fields captured from the in-app Find Ideas browser (with site cookies),
/// so Airbnb/Instagram photos are not fetched cookieless after Save.
struct FindIdeasPagePreview {
    var urlString: String
    var title: String?
    var notes: String?
    var imageJPEG: Data?
}

struct FindIdeasView: View {
    var onSavePage: (FindIdeasPagePreview) -> Void

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
                Text("Airbnb, Google, Maps, Instagram, TripAdvisor, and X open here. TikTok opens that app to search.")
            }
        }
        .navigationTitle("Find Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $browser) { page in
            FindIdeasBrowserSheet(
                startURL: page.url,
                onSave: { preview in
                    onSavePage(preview)
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
    var onSave: (FindIdeasPagePreview) -> Void
    var onDone: () -> Void

    @State private var currentURL: URL?
    @State private var isLoading = true
    @State private var isCapturing = false
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var goBackToken = 0
    @State private var goForwardToken = 0
    @State private var webView: WKWebView?

    var body: some View {
        NavigationStack {
            FindIdeasWebView(
                startURL: startURL,
                currentURL: $currentURL,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                goBackToken: goBackToken,
                goForwardToken: goForwardToken,
                webView: $webView
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
                    if isLoading || isCapturing {
                        ProgressView()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save 4 Two") {
                        Task { await captureAndSave() }
                    }
                    .disabled(currentURL == nil || isCapturing)
                }
            }
        }
    }

    @MainActor
    private func captureAndSave() async {
        guard let page = currentURL else { return }
        isCapturing = true
        defer { isCapturing = false }
        let absolute = OpenableURL.from(page.absoluteString)?.absoluteString ?? page.absoluteString
        var preview = FindIdeasPagePreview(urlString: absolute)
        if let webView {
            let captured = await FindIdeasPageCapture.capture(from: webView)
            preview.title = captured.title
            preview.notes = captured.notes
            preview.imageJPEG = captured.imageJPEG
        }
        onSave(preview)
    }
}

private enum FindIdeasPageCapture {
    struct Captured {
        var title: String?
        var notes: String?
        var imageJPEG: Data?
    }

    @MainActor
    static func capture(from webView: WKWebView) async -> Captured {
        var captured = Captured()

        // Prefer an in-page capture that uses the browser’s full cookie/session
        // access (not a cookieless URLSession refetch of a private CDN URL).
        if let payload = await captureInBrowser(webView) {
            if let title = payload.title, !title.isEmpty { captured.title = title }
            if let notes = payload.notes, !notes.isEmpty { captured.notes = notes }
            if let jpeg = payload.imageJPEG {
                captured.imageJPEG = jpeg
                return captured
            }
            for candidate in payload.imageURLs {
                if let jpeg = await downloadJPEG(candidate, webView: webView) {
                    captured.imageJPEG = jpeg
                    return captured
                }
            }
            return captured
        }

        // Last-resort meta scrape if async browser capture is unavailable.
        if let meta = await captureMetaOnly(webView) {
            captured.title = meta.title
            captured.notes = meta.notes
            for candidate in meta.imageURLs {
                if let jpeg = await downloadJPEG(candidate, webView: webView) {
                    captured.imageJPEG = jpeg
                    break
                }
            }
        }

        return captured
    }

    private struct BrowserPayload {
        var title: String?
        var notes: String?
        var imageJPEG: Data?
        var imageURLs: [URL]
    }

    @MainActor
    private static func captureMetaOnly(_ webView: WKWebView) async -> BrowserPayload? {
        let js = """
        (function() {
          function meta(sel, attr) {
            var el = document.querySelector(sel);
            return el ? (el.getAttribute(attr) || '') : '';
          }
          function first() {
            for (var i = 0; i < arguments.length; i++) {
              var v = (arguments[i] || '').trim();
              if (v) return v;
            }
            return '';
          }
          return JSON.stringify({
            title: first(
              meta('meta[property="og:title"]', 'content'),
              meta('meta[name="twitter:title"]', 'content'),
              document.title
            ),
            notes: first(
              meta('meta[property="og:description"]', 'content'),
              meta('meta[name="twitter:description"]', 'content'),
              meta('meta[name="description"]', 'content')
            ),
            image: first(
              meta('meta[property="og:image"]', 'content'),
              meta('meta[property="og:image:url"]', 'content'),
              meta('meta[property="og:image:secure_url"]', 'content'),
              meta('meta[name="twitter:image"]', 'content'),
              meta('meta[name="twitter:image:src"]', 'content')
            )
          });
        })();
        """
        guard let raw = try? await webView.evaluateJavaScript(js) as? String,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            return nil
        }
        var payload = BrowserPayload(title: nil, notes: nil, imageJPEG: nil, imageURLs: [])
        let title = json["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notes = json["notes"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { payload.title = title }
        if !notes.isEmpty { payload.notes = notes }
        let imageRaw = json["image"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !imageRaw.isEmpty,
           let imageURL = URL(string: imageRaw)
            ?? webView.url.flatMap({ URL(string: imageRaw, relativeTo: $0)?.absoluteURL }) {
            payload.imageURLs = [imageURL]
        }
        return payload
    }

    /// Pull title/notes/photo from the live page using the same session the user
    /// already has (logged-in / private listing photos).
    @MainActor
    private static func captureInBrowser(_ webView: WKWebView) async -> BrowserPayload? {
        let js = """
          function meta(sel, attr) {
            var el = document.querySelector(sel);
            return el ? (el.getAttribute(attr) || '') : '';
          }
          function first() {
            for (var i = 0; i < arguments.length; i++) {
              var v = (arguments[i] || '').trim();
              if (v) return v;
            }
            return '';
          }
          function bad(url) {
            var u = (url || '').toLowerCase();
            if (!u || u.indexOf('data:') === 0 || u.indexOf('blob:') === 0) return true;
            if (u.indexOf('logo') !== -1 || u.indexOf('favicon') !== -1) return true;
            if (u.indexOf('sprite') !== -1 || u.indexOf('/icon') !== -1) return true;
            if (u.indexOf('avatar') !== -1) return true;
            return false;
          }
          function abs(url) {
            try { return new URL(url, document.baseURI).href; } catch (e) { return ''; }
          }
          function push(list, url) {
            var a = abs(url);
            if (!a || bad(a) || list.indexOf(a) !== -1) return;
            list.push(a);
          }
          function srcsetBest(srcset) {
            if (!srcset) return '';
            var best = '', bestW = -1;
            srcset.split(',').forEach(function(part) {
              var bits = part.trim().split(/\\s+/);
              if (!bits[0]) return;
              var w = 0;
              if (bits[1] && bits[1].slice(-1) === 'w') w = parseInt(bits[1], 10) || 0;
              if (w >= bestW) { bestW = w; best = bits[0]; }
            });
            return best || srcset.split(',')[0].trim().split(/\\s+/)[0] || '';
          }

          var title = first(
            meta('meta[property="og:title"]', 'content'),
            meta('meta[name="twitter:title"]', 'content'),
            document.title
          );
          var notes = first(
            meta('meta[property="og:description"]', 'content'),
            meta('meta[name="twitter:description"]', 'content'),
            meta('meta[name="description"]', 'content')
          );

          var urls = [];
          push(urls, meta('meta[property="og:image"]', 'content'));
          push(urls, meta('meta[property="og:image:url"]', 'content'));
          push(urls, meta('meta[property="og:image:secure_url"]', 'content'));
          push(urls, meta('meta[name="twitter:image"]', 'content'));
          push(urls, meta('meta[name="twitter:image:src"]', 'content'));

          var scored = [];
          Array.prototype.forEach.call(document.images || [], function(img) {
            var w = Math.max(img.naturalWidth || 0, img.width || 0, img.clientWidth || 0);
            var h = Math.max(img.naturalHeight || 0, img.height || 0, img.clientHeight || 0);
            if (w < 120 || h < 120) return;
            var src = srcsetBest(img.currentSrc || img.getAttribute('srcset') || '') || img.src || '';
            if (bad(src)) return;
            scored.push({ url: abs(src), area: w * h, el: img });
          });
          scored.sort(function(a, b) { return b.area - a.area; });
          scored.forEach(function(s) { push(urls, s.url); });

          async function blobToDataURL(blob) {
            return await new Promise(function(resolve, reject) {
              var reader = new FileReader();
              reader.onload = function() { resolve(reader.result); };
              reader.onerror = reject;
              reader.readAsDataURL(blob);
            });
          }

          async function fetchDataURL(url) {
            try {
              var res = await fetch(url, { credentials: 'include', mode: 'cors', cache: 'force-cache' });
              if (!res.ok) return '';
              var blob = await res.blob();
              if (!blob || blob.size < 800) return '';
              return await blobToDataURL(blob);
            } catch (e) {
              return '';
            }
          }

          function canvasFromImg(img) {
            try {
              var w = img.naturalWidth || img.width || 0;
              var h = img.naturalHeight || img.height || 0;
              if (w < 120 || h < 120) return '';
              var canvas = document.createElement('canvas');
              var max = 1600;
              var scale = Math.min(1, max / Math.max(w, h));
              canvas.width = Math.max(1, Math.round(w * scale));
              canvas.height = Math.max(1, Math.round(h * scale));
              var ctx = canvas.getContext('2d');
              ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
              return canvas.toDataURL('image/jpeg', 0.82);
            } catch (e) {
              return '';
            }
          }

          var dataURL = '';
          for (var i = 0; i < urls.length && !dataURL; i++) {
            dataURL = await fetchDataURL(urls[i]);
          }
          if (!dataURL) {
            for (var j = 0; j < scored.length && !dataURL; j++) {
              dataURL = canvasFromImg(scored[j].el);
            }
          }

          return {
            title: title,
            notes: notes,
            dataURL: dataURL || '',
            images: urls.slice(0, 8)
          };
        """

        guard let result = try? await webView.callAsyncJavaScript(
            js,
            arguments: [:],
            in: nil,
            in: .page
        ) as? [String: Any] else {
            return nil
        }

        var payload = BrowserPayload(title: nil, notes: nil, imageJPEG: nil, imageURLs: [])
        if let title = result["title"] as? String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { payload.title = trimmed }
        }
        if let notes = result["notes"] as? String {
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { payload.notes = trimmed }
        }
        if let dataURL = result["dataURL"] as? String, let jpeg = jpegFromDataURL(dataURL) {
            payload.imageJPEG = jpeg
        }
        if let images = result["images"] as? [String] {
            payload.imageURLs = images.compactMap { raw in
                URL(string: raw)
                    ?? webView.url.flatMap { URL(string: raw, relativeTo: $0)?.absoluteURL }
            }
        }
        return payload
    }

    private static func jpegFromDataURL(_ dataURL: String) -> Data? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let encoded = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              let image = UIImage(data: data) else {
            return nil
        }
        return PhotoJPEG.compressed(image)
    }

    /// Fallback: download with the browser’s cookies so private / login-gated CDNs still return the photo.
    private static func downloadJPEG(_ url: URL, webView: WKWebView) async -> Data? {
        let cookies = await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/jpeg,image/png,image/webp,image/apng,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let referer = webView.url?.absoluteString {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if !cookies.isEmpty {
            let header = HTTPCookie.requestHeaderFields(with: cookies)
            if let cookieHeader = header["Cookie"] {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            return PhotoJPEG.compressed(image)
        } catch {
            return nil
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
    @Binding var webView: WKWebView?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Persist cookies/session so Save can download og:image with the same access
        // the listing page already has (private / logged-in photos).
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
        web.addObserver(context.coordinator, forKeyPath: "URL", options: .new, context: nil)
        web.addObserver(context.coordinator, forKeyPath: "loading", options: .new, context: nil)
        web.addObserver(context.coordinator, forKeyPath: "canGoBack", options: .new, context: nil)
        web.addObserver(context.coordinator, forKeyPath: "canGoForward", options: .new, context: nil)
        DispatchQueue.main.async {
            self.webView = web
        }
        web.load(URLRequest(url: startURL))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if webView !== web {
            DispatchQueue.main.async { self.webView = web }
        }
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
                // Airbnb (and similar) try to jump into their app via custom
                // schemes. Keep browsing on https so the listing still loads.
                if let https = OpenableURL.httpsEquivalent(url) {
                    webView.load(URLRequest(url: https))
                }
                return
            }
            decisionHandler(.allow)
        }
    }
}
