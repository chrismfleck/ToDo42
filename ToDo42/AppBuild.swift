import Foundation

enum AppBuild {
    /// MUST equal CURRENT_PROJECT_VERSION / CFBundleVersion (plist). Never diverge.
    /// Use: bash scripts/bump_build.sh <n>  — bumps AppBuild + Xcode + confirm_build together.
    /// UI reads this stamp (not Info.plist) so a stale install cannot hide the real code.
    static let number = "206"

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
