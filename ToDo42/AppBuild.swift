import Foundation

enum AppBuild {
    static var number: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Always include the build integer so TestFlight / local installs are obvious.
    static var label: String {
        "Build \(number)"
    }

    static var versionLine: String {
        "Version \(marketing) · \(label)"
    }
}
