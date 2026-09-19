import Foundation
import SwiftUI
import UIKit
import WebKit

/// Turns saved / shared links into URLs that open reliably from Save 4 Two.
enum OpenableURL {
    static func from(_ string: String?) -> URL? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let url = parse(raw) {
            return normalized(url)
        }
        if let detected = firstRawHTTPURL(in: raw), let url = parse(detected) {
            return normalized(url)
        }
        return nil
    }

    static func firstRawHTTPURL(in string: String) -> String? {
        let pattern = #"https?://[^\s<>\"'\)\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              let swiftRange = Range(match.range, in: string) else {
            return nil
        }
        var found = String(string[swiftRange])
        while let last = found.last, ".,:;!?)]}>\"".contains(last) {
            found.removeLast()
        }
        return found
    }

    static func isAirbnb(_ url: URL) -> Bool {
        isAirbnbHost(url) || url.scheme?.lowercased() == "airbnb"
    }

    static func openExternally(_ url: URL) {
        UIApplication.shared.open(normalized(url))
    }

    static func httpsEquivalent(_ url: URL) -> URL? {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme != "http", scheme != "https", scheme != "about" else { return nil }
        if scheme == "airbnb" {
            return airbnbHTTPS(fromDeepLink: url)
        }
        return nil
    }

    private static func parse(_ raw: String) -> URL? {
        if let url = URL(string: raw) { return url }
        if let components = URLComponents(string: raw), let url = components.url { return url }
        if let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let url = URL(string: encoded) {
            return url
        }
        return nil
    }

    private static func normalized(_ url: URL) -> URL {
        if let https = httpsEquivalent(url) {
            return https
        }
        if isAirbnbHost(url), let roomID = airbnbRoomID(from: url) {
            return URL(string: "https://www.airbnb.com/rooms/\(roomID)") ?? url
        }
        return url
    }

    private static func isAirbnbHost(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("airbnb.") || host.contains("abnb.me")
    }

    private static func airbnbRoomID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let roomsIndex = parts.firstIndex(of: "rooms"),
              parts.indices.contains(roomsIndex + 1) else {
            return nil
        }
        let candidate = parts[roomsIndex + 1]
        guard candidate.allSatisfy(\.isNumber), !candidate.isEmpty else { return nil }
        return candidate
    }

    private static func airbnbHTTPS(fromDeepLink url: URL) -> URL? {
        let host = (url.host ?? "").lowercased()
        let pathParts = url.path.split(separator: "/").map(String.init)

        if host == "rooms", let id = pathParts.first, id.allSatisfy(\.isNumber) {
            return URL(string: "https://www.airbnb.com/rooms/\(id)")
        }
        if let id = airbnbRoomID(from: url) {
            return URL(string: "https://www.airbnb.com/rooms/\(id)")
        }
        if !host.isEmpty {
            let path = url.path.isEmpty ? "" : url.path
            return URL(string: "https://www.airbnb.com/\(host)\(path)")
        }
        return URL(string: "https://www.airbnb.com/")
    }
}

struct LinkBrowserPage: Identifiable {
    let id = UUID()
    let url: URL
}

/// In-app browser used for Airbnb (same approach as Find Ideas).
struct LinkBrowserSheet: View {
    let page: LinkBrowserPage
    var onDone: () -> Void

    @State private var currentURL: URL?
    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var goBackToken = 0

    var body: some View {
        NavigationStack {
            LinkBrowserWebView(
                startURL: page.url,
                currentURL: $currentURL,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                goBackToken: goBackToken
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(currentURL?.host ?? page.url.host ?? "Link")
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
                    Spacer()
                    if isLoading {
                        ProgressView()
                    }
                }
            }
        }
    }
}

private struct LinkBrowserWebView: UIViewRepresentable {
    let startURL: URL
    @Binding var currentURL: URL?
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    var goBackToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
        web.addObserver(context.coordinator, forKeyPath: "URL", options: .new, context: nil)
        web.addObserver(context.coordinator, forKeyPath: "loading", options: .new, context: nil)
        web.addObserver(context.coordinator, forKeyPath: "canGoBack", options: .new, context: nil)
        web.load(URLRequest(url: startURL))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if goBackToken != context.coordinator.lastGoBackToken {
            context.coordinator.lastGoBackToken = goBackToken
            if web.canGoBack { web.goBack() }
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.removeObserver(coordinator, forKeyPath: "URL")
        web.removeObserver(coordinator, forKeyPath: "loading")
        web.removeObserver(coordinator, forKeyPath: "canGoBack")
        web.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LinkBrowserWebView
        var lastGoBackToken = 0

        init(_ parent: LinkBrowserWebView) {
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
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
               scheme != "http", scheme != "https", scheme != "about" {
                decisionHandler(.cancel)
                if let https = OpenableURL.httpsEquivalent(url) {
                    webView.load(URLRequest(url: https))
                }
                return
            }
            decisionHandler(.allow)
        }
    }
}
