import Foundation

enum AppBuild {
    /// Bump together with CURRENT_PROJECT_VERSION in the Xcode project.
    /// UI reads this stamp (not Info.plist) so a stale install cannot hide the real code.
    static let number = "121"

    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var label: String {
        "Build \(number)"
    }

    static var versionLine: String {
        let plist = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        if plist == number {
            return "Version \(marketing) · \(label)"
        }
        return "Version \(marketing) · \(label) (plist \(plist))"
    }
}
