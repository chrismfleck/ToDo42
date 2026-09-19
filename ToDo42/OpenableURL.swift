import Foundation
import SafariServices
import UIKit

/// Turns saved / shared links into URLs that open reliably from Save 4 Two.
///
/// Some Airbnb room links fail when iOS hands them to the Airbnb app. We strip
/// tracking to `/rooms/{id}` and present `SFSafariViewController` from the
/// topmost UIKit controller (item pages are already a SwiftUI fullScreenCover,
/// so nested SwiftUI covers/sheets often never appear).
enum OpenableURL {
    static func from(_ string: String?) -> URL? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let url = parse(raw) {
            return normalized(url)
        }
        return nil
    }

    static func isAirbnb(_ url: URL) -> Bool {
        isAirbnbHost(url) || url.scheme?.lowercased() == "airbnb"
    }

    static func open(_ string: String?) {
        guard let url = from(string) else { return }
        open(url)
    }

    static func open(_ url: URL) {
        let target = normalized(url)
        if isAirbnb(target) {
            presentSafari(target)
        } else {
            UIApplication.shared.open(target)
        }
    }

    static func httpsEquivalent(_ url: URL) -> URL? {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme != "http", scheme != "https", scheme != "about" else { return nil }
        if scheme == "airbnb" {
            return airbnbHTTPS(fromDeepLink: url)
        }
        return nil
    }

    private static func presentSafari(_ url: URL) {
        DispatchQueue.main.async {
            let safari = SFSafariViewController(url: url)
            safari.dismissButtonStyle = .close
            safari.preferredControlTintColor = UIColor(red: 0.10, green: 0.45, blue: 0.90, alpha: 1)
            safari.modalPresentationStyle = .pageSheet

            guard let presenter = topMostViewController() else {
                UIApplication.shared.open(url)
                return
            }

            if presenter is SFSafariViewController {
                presenter.dismiss(animated: false) {
                    topMostViewController()?.present(safari, animated: true)
                }
                return
            }

            if presenter.presentedViewController != nil {
                presenter.presentedViewController?.present(safari, animated: true)
                return
            }

            presenter.present(safari, animated: true)
        }
    }

    private static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        if let nav = top as? UINavigationController {
            top = nav.visibleViewController ?? top
        }
        if let tab = top as? UITabBarController {
            top = tab.selectedViewController ?? top
            while let presented = top.presentedViewController {
                top = presented
            }
        }
        return top
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
        (url.host ?? "").lowercased().contains("airbnb.")
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
