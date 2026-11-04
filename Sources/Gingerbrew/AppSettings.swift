import Foundation
import Observation

/// User preferences, persisted in `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    /// Hours between background update checks; 0 turns them off.
    var checkIntervalHours: Int {
        didSet { defaults.set(checkIntervalHours, forKey: Keys.checkInterval) }
    }

    /// Also report casks that update themselves (`brew outdated --greedy`).
    var includeAutoUpdatingCasks: Bool {
        didSet { defaults.set(includeAutoUpdatingCasks, forKey: Keys.greedy) }
    }

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }

    /// Whether the Dependencies section of the main list is expanded.
    var dependenciesExpanded: Bool {
        didSet { defaults.set(dependenciesExpanded, forKey: Keys.dependenciesExpanded) }
    }

    var lastUpdateCheck: Date? {
        didSet { defaults.set(lastUpdateCheck, forKey: Keys.lastCheck) }
    }

    static let intervalChoices = [1, 6, 12, 24]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.checkInterval: 6,
            Keys.greedy: false,
            Keys.notifications: true,
            Keys.dependenciesExpanded: false,
        ])
        checkIntervalHours = defaults.integer(forKey: Keys.checkInterval)
        includeAutoUpdatingCasks = defaults.bool(forKey: Keys.greedy)
        notificationsEnabled = defaults.bool(forKey: Keys.notifications)
        dependenciesExpanded = defaults.bool(forKey: Keys.dependenciesExpanded)
        lastUpdateCheck = defaults.object(forKey: Keys.lastCheck) as? Date
    }

    private enum Keys {
        static let checkInterval = "checkIntervalHours"
        static let greedy = "includeAutoUpdatingCasks"
        static let notifications = "notificationsEnabled"
        static let lastCheck = "lastUpdateCheck"
        static let dependenciesExpanded = "dependenciesExpanded"
    }
}
