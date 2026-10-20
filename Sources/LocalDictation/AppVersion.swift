import Foundation

/// Read the running bundle, not a source constant that can drift from the installed app.
enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "Development"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        return "Brief \(version) (build \(build))"
    }
}
