import AppKit
import GingerbrewCore
import ServiceManagement
import UserNotifications

/// User notifications. They need a real `.app` bundle, so they're skipped under `swift run`.
@MainActor
enum Notifier {
    private static let delegate = NotificationDelegate()

    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static func requestAuthorization() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String?) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    // Show banners even though Gingerbrew is technically the active app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

/// "Launch at login", via the system login items list.
@MainActor
enum LoginItem {
    static var isAvailable: Bool { Notifier.isAvailable }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Icons and developer names for packages.
@MainActor
enum PackageMetadata {
    private static var iconCache: [String: NSImage] = [:]
    private static var missingIcons: Set<String> = []

    /// Where an installed cask's app lives, if it can be found.
    static func appURL(for package: Package) -> URL? {
        guard package.kind == .cask, package.isInstalled else { return nil }
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        for path in package.appPaths {
            let expanded = (path as NSString).expandingTildeInPath
            let name = (expanded as NSString).lastPathComponent
            for candidate in [expanded, "\(home)/Applications/\(name)"] where fileManager.fileExists(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    static func icon(for package: Package) -> NSImage? {
        if let cached = iconCache[package.id] { return cached }
        if missingIcons.contains(package.id) { return nil }
        guard let url = appURL(for: package) else {
            if package.isInstalled { missingIcons.insert(package.id) }
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[package.id] = image
        return image
    }

    static func developer(for package: Package) -> String? {
        if let url = appURL(for: package),
           let copyright = Bundle(url: url)?.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
           let name = DeveloperName.from(copyright: copyright) {
            return name
        }
        return DeveloperName.from(homepage: package.homepage)
    }
}
