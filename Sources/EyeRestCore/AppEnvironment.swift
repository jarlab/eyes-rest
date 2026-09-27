import Foundation

/// Facts about how the running executable was packaged and where it lives.
public enum AppEnvironment {
    /// True when running from an `.app` bundle (as opposed to `swift run`).
    public static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    /// True when the bundle lives in `/Applications` or `~/Applications` (required for a reliable login item).
    public static var isInstalledInApplications: Bool {
        isInApplicationsFolder(Bundle.main.bundleURL, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    static func isInApplicationsFolder(_ bundleURL: URL, home: URL) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        let folders = [
            "/Applications/",
            home.standardizedFileURL.appendingPathComponent("Applications").path + "/",
        ]
        return folders.contains { path.hasPrefix($0) }
    }
}
