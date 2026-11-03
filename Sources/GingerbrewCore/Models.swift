import Foundation

/// Homebrew has two package types: command-line formulae and app casks.
public enum PackageKind: String, Codable, Sendable, Hashable, CaseIterable {
    case formula
    case cask

    /// The flag that disambiguates a name for `brew` subcommands.
    public var cliFlag: String { self == .formula ? "--formula" : "--cask" }

    public var displayName: String { self == .formula ? "Formula" : "Cask" }
}

/// Uniquely identifies a package across both kinds (a formula and a cask may share a name).
public struct PackageRef: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    public let kind: PackageKind
    public let name: String

    public init(kind: PackageKind, name: String) {
        self.kind = kind
        self.name = name
    }

    public var id: String { "\(kind.rawValue):\(name)" }
    public var description: String { id }

    /// The short name used for display and matching (`user/tap/foo` → `foo`).
    public var shortName: String { name.split(separator: "/").last.map(String.init) ?? name }
}

/// A formula or cask, installed or not, normalised from Homebrew's JSON.
public struct Package: Identifiable, Hashable, Sendable {
    public var ref: PackageRef
    public var fullName: String
    public var displayName: String
    public var summary: String?
    public var homepage: URL?
    public var tap: String?
    public var license: String?

    /// The newest installed version, or `nil` when the package is not installed.
    public var installedVersion: String?
    /// All installed versions (formulae can keep several kegs).
    public var installedVersions: [String]
    /// The newest version Homebrew knows about.
    public var latestVersion: String?
    public var isOutdated: Bool
    public var isPinned: Bool
    /// `false` when a formula was pulled in only as a dependency.
    public var installedOnRequest: Bool
    public var installedDate: Date?
    /// Casks that update themselves (Homebrew only upgrades them with `--greedy`).
    public var autoUpdates: Bool
    public var isDeprecated: Bool
    public var isDisabled: Bool
    public var caveats: String?
    /// Direct dependencies (formulae and casks).
    public var dependencies: [PackageRef]
    /// For casks: candidate locations of the installed `.app` bundles.
    public var appPaths: [String]

    public init(
        ref: PackageRef,
        fullName: String? = nil,
        displayName: String? = nil,
        summary: String? = nil,
        homepage: URL? = nil,
        tap: String? = nil,
        license: String? = nil,
        installedVersion: String? = nil,
        installedVersions: [String] = [],
        latestVersion: String? = nil,
        isOutdated: Bool = false,
        isPinned: Bool = false,
        installedOnRequest: Bool = true,
        installedDate: Date? = nil,
        autoUpdates: Bool = false,
        isDeprecated: Bool = false,
        isDisabled: Bool = false,
        caveats: String? = nil,
        dependencies: [PackageRef] = [],
        appPaths: [String] = []
    ) {
        self.ref = ref
        self.fullName = fullName ?? ref.name
        self.displayName = displayName ?? ref.name
        self.summary = summary
        self.homepage = homepage
        self.tap = tap
        self.license = license
        self.installedVersion = installedVersion
        self.installedVersions = installedVersions
        self.latestVersion = latestVersion
        self.isOutdated = isOutdated
        self.isPinned = isPinned
        self.installedOnRequest = installedOnRequest
        self.installedDate = installedDate
        self.autoUpdates = autoUpdates
        self.isDeprecated = isDeprecated
        self.isDisabled = isDisabled
        self.caveats = caveats
        self.dependencies = dependencies
        self.appPaths = appPaths
    }

    public var id: String { ref.id }
    public var kind: PackageKind { ref.kind }
    public var name: String { ref.name }
    public var isInstalled: Bool { installedVersion != nil }

    /// Builds a lightweight, not-installed package from a search index entry.
    public init(entry: IndexEntry) {
        self.init(
            ref: entry.ref,
            displayName: entry.displayName,
            summary: entry.summary,
            homepage: entry.homepage.flatMap(URL.init(string:)),
            tap: entry.ref.kind == .formula ? "homebrew/core" : "homebrew/cask",
            latestVersion: entry.version
        )
    }

    /// Whether `other` is the package this dependency reference points at.
    public func matches(_ dependency: PackageRef) -> Bool {
        dependency.kind == kind && (dependency.name == name || dependency.name == fullName)
    }
}

/// A row from `brew outdated --json=v2`.
public struct OutdatedEntry: Hashable, Sendable {
    public let ref: PackageRef
    public let installedVersions: [String]
    public let currentVersion: String
    public let pinned: Bool

    public init(ref: PackageRef, installedVersions: [String], currentVersion: String, pinned: Bool) {
        self.ref = ref
        self.installedVersions = installedVersions
        self.currentVersion = currentVersion
        self.pinned = pinned
    }
}
