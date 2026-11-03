import Foundation

/// Turns `brew … --json=v2` output into `Package` values.
public enum BrewParser {
    // MARK: brew info --json=v2

    public static func parseInfo(_ data: Data) throws -> [Package] {
        let raw = try JSONDecoder().decode(RawInfo.self, from: data)
        let formulae = (raw.formulae ?? []).map(package(from:))
        let casks = (raw.casks ?? []).map(package(from:))
        return formulae + casks
    }

    static func package(from raw: RawFormula) -> Package {
        // Newest keg last: sort by install time when present.
        let kegs = (raw.installed ?? []).sorted { ($0.time ?? 0) < ($1.time ?? 0) }
        let newest = kegs.last
        var latest = raw.versions?.stable
        if let stable = latest, let revision = raw.revision, revision > 0 {
            latest = "\(stable)_\(revision)"
        }
        return Package(
            ref: PackageRef(kind: .formula, name: raw.name),
            fullName: raw.fullName ?? raw.name,
            displayName: raw.name,
            summary: raw.desc.nilIfEmpty,
            homepage: raw.homepage.flatMap(URL.init(string:)),
            tap: raw.tap,
            license: raw.license,
            installedVersion: newest?.version,
            installedVersions: kegs.map(\.version),
            latestVersion: latest,
            isOutdated: raw.outdated ?? false,
            isPinned: raw.pinned ?? false,
            installedOnRequest: newest?.installedOnRequest ?? true,
            installedDate: newest?.time.map { Date(timeIntervalSince1970: $0) },
            isDeprecated: raw.deprecated ?? false,
            isDisabled: raw.disabled ?? false,
            caveats: raw.caveats.nilIfEmpty,
            dependencies: (raw.dependencies ?? []).map { PackageRef(kind: .formula, name: $0) }
        )
    }

    static func package(from raw: RawCask) -> Package {
        let dependsOn = raw.dependsOn
        let dependencies =
            (dependsOn?["formula"]?.strings ?? []).map { PackageRef(kind: .formula, name: $0) }
            + (dependsOn?["cask"]?.strings ?? []).map { PackageRef(kind: .cask, name: $0) }
        return Package(
            ref: PackageRef(kind: .cask, name: raw.token),
            fullName: raw.fullToken ?? raw.token,
            displayName: raw.name?.first ?? raw.token,
            summary: raw.desc.nilIfEmpty,
            homepage: raw.homepage.flatMap(URL.init(string:)),
            tap: raw.tap,
            installedVersion: raw.installed,
            installedVersions: raw.installed.map { [$0] } ?? [],
            latestVersion: raw.version,
            isOutdated: raw.outdated ?? false,
            isPinned: raw.pinned ?? false,
            installedDate: raw.installedTime.map { Date(timeIntervalSince1970: $0) },
            autoUpdates: raw.autoUpdates ?? false,
            isDeprecated: raw.deprecated ?? false,
            isDisabled: raw.disabled ?? false,
            caveats: raw.caveats.nilIfEmpty,
            dependencies: dependencies,
            appPaths: appPaths(from: raw.artifacts ?? [])
        )
    }

    /// Finds `.app` bundle locations in a cask's `artifacts`.
    ///
    /// Homebrew has emitted two shapes over time:
    /// `{"app": ["Foo.app"], "target": "/Applications/Foo.app"}` and
    /// `{"app": ["Foo.app", {"target": "Bar.app"}]}`.
    static func appPaths(from artifacts: [JSONValue]) -> [String] {
        var paths: [String] = []
        for artifact in artifacts {
            guard let app = artifact["app"]?.array, let source = app.first?.string else { continue }
            let nestedTarget = app.dropFirst().first?["target"]?.string
            let target = artifact["target"]?.string ?? nestedTarget
            if let target {
                paths.append(target.hasPrefix("/") || target.hasPrefix("~")
                    ? target
                    : "/Applications/\(target)")
            } else {
                paths.append("/Applications/\(source)")
            }
        }
        return paths
    }

    // MARK: brew outdated --json=v2

    public static func parseOutdated(_ data: Data) throws -> [OutdatedEntry] {
        let raw = try JSONDecoder().decode(RawOutdated.self, from: data)
        func entries(_ items: [RawOutdated.Item]?, _ kind: PackageKind) -> [OutdatedEntry] {
            (items ?? []).map {
                OutdatedEntry(
                    ref: PackageRef(kind: kind, name: $0.name),
                    installedVersions: $0.installedVersions ?? [],
                    currentVersion: $0.currentVersion,
                    pinned: $0.pinned ?? false
                )
            }
        }
        return entries(raw.formulae, .formula) + entries(raw.casks, .cask)
    }

    /// Applies `brew outdated` as the source of truth for update availability,
    /// since it respects options such as `--greedy` that `brew info` ignores.
    public static func merge(_ packages: [Package], outdated: [OutdatedEntry]) -> [Package] {
        var byRef: [PackageRef: OutdatedEntry] = [:]
        for entry in outdated { byRef[entry.ref] = entry }
        return packages.map { package in
            var package = package
            let key = PackageRef(kind: package.kind, name: package.name)
            let fullKey = PackageRef(kind: package.kind, name: package.fullName)
            if let entry = byRef[key] ?? byRef[fullKey] {
                package.isOutdated = true
                package.latestVersion = entry.currentVersion
                package.isPinned = package.isPinned || entry.pinned
            } else {
                package.isOutdated = false
            }
            return package
        }
    }
}

// MARK: - Raw JSON shapes

struct RawInfo: Decodable {
    let formulae: [RawFormula]?
    let casks: [RawCask]?
}

struct RawFormula: Decodable {
    struct Versions: Decodable { let stable: String? }
    struct Keg: Decodable {
        let version: String
        let time: Double?
        let installedOnRequest: Bool?

        enum CodingKeys: String, CodingKey {
            case version, time
            case installedOnRequest = "installed_on_request"
        }
    }

    let name: String
    let fullName: String?
    let tap: String?
    let desc: String?
    let license: String?
    let homepage: String?
    let versions: Versions?
    let revision: Int?
    let installed: [Keg]?
    let outdated: Bool?
    let pinned: Bool?
    let deprecated: Bool?
    let disabled: Bool?
    let dependencies: [String]?
    let caveats: String?

    enum CodingKeys: String, CodingKey {
        case name, tap, desc, license, homepage, versions, revision, installed
        case outdated, pinned, deprecated, disabled, dependencies, caveats
        case fullName = "full_name"
    }
}

struct RawCask: Decodable {
    let token: String
    let fullToken: String?
    let tap: String?
    let name: [String]?
    let desc: String?
    let homepage: String?
    let version: String?
    let installed: String?
    let installedTime: Double?
    let outdated: Bool?
    let pinned: Bool?
    let autoUpdates: Bool?
    let deprecated: Bool?
    let disabled: Bool?
    let caveats: String?
    let artifacts: [JSONValue]?
    let dependsOn: JSONValue?

    enum CodingKeys: String, CodingKey {
        case token, tap, name, desc, homepage, version, installed, outdated, pinned
        case deprecated, disabled, caveats, artifacts
        case fullToken = "full_token"
        case installedTime = "installed_time"
        case autoUpdates = "auto_updates"
        case dependsOn = "depends_on"
    }
}

struct RawOutdated: Decodable {
    struct Item: Decodable {
        let name: String
        let installedVersions: [String]?
        let currentVersion: String
        let pinned: Bool?

        enum CodingKeys: String, CodingKey {
            case name, pinned
            case installedVersions = "installed_versions"
            case currentVersion = "current_version"
        }
    }

    let formulae: [Item]?
    let casks: [Item]?
}

extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
