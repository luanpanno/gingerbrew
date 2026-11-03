import Foundation

public enum BrewError: LocalizedError, Sendable {
    case commandFailed(command: String, status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status, message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "`brew \(command)` failed with exit code \(status)."
                : detail
        }
    }
}

/// Something the user can ask Homebrew to do to a package.
public enum PackageAction: Hashable, Sendable {
    case install(PackageRef)
    case upgrade(PackageRef)
    case upgradeAll(greedy: Bool)
    case uninstall(PackageRef)
    /// Casks: also delete the app's support files (`--zap`).
    /// Formulae: remove every installed version (`--force`).
    case uninstallCompletely(PackageRef)

    public var ref: PackageRef? {
        switch self {
        case .install(let ref), .upgrade(let ref), .uninstall(let ref), .uninstallCompletely(let ref): ref
        case .upgradeAll: nil
        }
    }

    public var arguments: [String] {
        switch self {
        case .install(let ref):
            ["install", ref.kind.cliFlag, ref.name]
        case .upgrade(let ref):
            // A cask can only be listed as outdated with --greedy if it auto-updates,
            // so pass it to make sure the upgrade actually happens.
            ["upgrade", ref.kind.cliFlag] + (ref.kind == .cask ? ["--greedy"] : []) + [ref.name]
        case .upgradeAll(let greedy):
            ["upgrade"] + (greedy ? ["--greedy"] : [])
        case .uninstall(let ref):
            ["uninstall", ref.kind.cliFlag, ref.name]
        case .uninstallCompletely(let ref):
            ["uninstall", ref.kind.cliFlag, ref.kind == .cask ? "--zap" : "--force", ref.name]
        }
    }

    /// Present-tense title shown while running, e.g. "Upgrading wget".
    public func progressTitle(displayName: String?) -> String {
        let name = displayName ?? ref?.name ?? ""
        switch self {
        case .install: return "Installing \(name)"
        case .upgrade: return "Upgrading \(name)"
        case .upgradeAll: return "Upgrading all packages"
        case .uninstall, .uninstallCompletely: return "Removing \(name)"
        }
    }

    /// Past-tense title shown when finished, e.g. "Upgraded wget".
    public func completedTitle(displayName: String?) -> String {
        let name = displayName ?? ref?.name ?? ""
        switch self {
        case .install: return "Installed \(name)"
        case .upgrade: return "Upgraded \(name)"
        case .upgradeAll: return "All packages upgraded"
        case .uninstall, .uninstallCompletely: return "Removed \(name)"
        }
    }
}

/// Talks to the `brew` executable.
public final class BrewService: Sendable {
    public let brewURL: URL
    public let askpassURL: URL?

    public init(brewURL: URL, askpassURL: URL? = nil) {
        self.brewURL = brewURL
        self.askpassURL = askpassURL
    }

    /// Finds `brew` in the standard Apple Silicon and Intel prefixes.
    public static func locateBrew(fileManager: FileManager = .default) -> URL? {
        let candidates = [
            ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"].map { "\($0)/bin/brew" },
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ].compactMap { $0 }
        return candidates
            .first { fileManager.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// The Homebrew prefix, e.g. `/opt/homebrew`.
    public var prefix: String {
        brewURL.deletingLastPathComponent().deletingLastPathComponent().path
    }

    /// Apps launched from Finder get a minimal environment, so build one brew is happy with.
    public var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(prefix)/bin:\(prefix)/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"  // Gingerbrew runs `brew update` itself.
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        env["HOMEBREW_NO_EMOJI"] = "1"
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        if let askpassURL { env["SUDO_ASKPASS"] = askpassURL.path }
        return env
    }

    // MARK: Queries

    public func run(_ arguments: [String]) async throws -> Data {
        let output = try await ProcessRunner.run(brewURL, arguments: arguments, environment: environment)
        guard output.succeeded else {
            throw BrewError.commandFailed(
                command: arguments.joined(separator: " "),
                status: output.status,
                message: output.stderr)
        }
        return output.stdout
    }

    /// Every installed formula and cask, with update availability.
    public func installedPackages(includeAutoUpdatingCasks greedy: Bool) async throws -> [Package] {
        async let info = run(["info", "--json=v2", "--installed"])
        async let outdated = run(["outdated", "--json=v2"] + (greedy ? ["--greedy"] : []))
        let packages = try BrewParser.parseInfo(try await info)
        let entries = try BrewParser.parseOutdated(try await outdated)
        return BrewParser.merge(packages, outdated: entries)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Full information about one package, installed or not.
    public func info(_ ref: PackageRef) async throws -> Package? {
        let data = try await run(["info", "--json=v2", ref.kind.cliFlag, ref.name])
        return try BrewParser.parseInfo(data).first
    }

    /// Refreshes Homebrew's own package metadata (`brew update`).
    public func update() async throws {
        _ = try await run(["update", "--quiet"])
    }

    public func version() async -> String? {
        guard let data = try? await run(["--version"]) else { return nil }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n").first
            .map { $0.replacingOccurrences(of: "Homebrew ", with: "") }
    }

    // MARK: Actions

    /// Runs an action, reporting output line by line. Returns the exit status.
    public func perform(
        _ action: PackageAction,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        try await ProcessRunner.stream(
            brewURL, arguments: action.arguments, environment: environment, onLine: onLine)
    }
}
