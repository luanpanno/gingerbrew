import Foundation
import Testing
@testable import GingerbrewCore

@Suite("BrewParser")
struct BrewParserTests {
    static let infoJSON = Data(#"""
    {
      "formulae": [
        {
          "name": "wget",
          "full_name": "wget",
          "tap": "homebrew/core",
          "desc": "Internet file retriever",
          "license": "GPL-3.0-or-later",
          "homepage": "https://www.gnu.org/software/wget/",
          "versions": { "stable": "1.25.0", "head": "HEAD", "bottle": true },
          "revision": 1,
          "dependencies": ["libidn2", "openssl@3"],
          "installed": [
            { "version": "1.24.5", "time": 1700000000, "installed_on_request": true, "runtime_dependencies": [] },
            { "version": "1.25.0", "time": 1710000000, "installed_on_request": true, "runtime_dependencies": [] }
          ],
          "outdated": false,
          "pinned": false,
          "deprecated": false,
          "disabled": false,
          "caveats": "  "
        },
        {
          "name": "libidn2",
          "full_name": "libidn2",
          "tap": "homebrew/core",
          "desc": "International domain name library",
          "homepage": "https://www.gnu.org/software/libidn/",
          "versions": { "stable": "2.3.7" },
          "revision": 0,
          "dependencies": [],
          "installed": [{ "version": "2.3.7", "time": 1700000000, "installed_on_request": false }],
          "outdated": false
        }
      ],
      "casks": [
        {
          "token": "firefox",
          "full_token": "firefox",
          "tap": "homebrew/cask",
          "name": ["Mozilla Firefox"],
          "desc": "Web browser",
          "homepage": "https://www.mozilla.org/firefox/",
          "version": "140.0",
          "installed": "139.0",
          "installed_time": 1720000000,
          "outdated": false,
          "auto_updates": true,
          "depends_on": { "macos": { ">=": ["12"] } },
          "artifacts": [
            { "uninstall": [{ "quit": "org.mozilla.firefox" }] },
            { "app": ["Firefox.app"], "target": "/Applications/Firefox.app" },
            { "zap": [{ "trash": ["~/Library/Caches/Firefox"] }] }
          ]
        },
        {
          "token": "some-tool",
          "name": ["Some Tool"],
          "version": "2.0",
          "installed": "2.0",
          "depends_on": { "formula": "python@3.13", "cask": ["xquartz"] },
          "artifacts": [{ "app": ["Some Tool.app", { "target": "Renamed.app" }] }]
        }
      ]
    }
    """#.utf8)

    @Test func parsesFormulae() throws {
        let packages = try BrewParser.parseInfo(Self.infoJSON)
        let wget = try #require(packages.first { $0.name == "wget" })
        #expect(wget.kind == .formula)
        #expect(wget.summary == "Internet file retriever")
        #expect(wget.installedVersion == "1.25.0", "newest keg by install time")
        #expect(wget.installedVersions == ["1.24.5", "1.25.0"])
        #expect(wget.latestVersion == "1.25.0_1", "revision is appended")
        #expect(wget.installedOnRequest)
        #expect(wget.caveats == nil, "blank caveats are dropped")
        #expect(wget.dependencies == [
            PackageRef(kind: .formula, name: "libidn2"),
            PackageRef(kind: .formula, name: "openssl@3"),
        ])
        #expect(wget.installedDate == Date(timeIntervalSince1970: 1_710_000_000))

        let libidn2 = try #require(packages.first { $0.name == "libidn2" })
        #expect(!libidn2.installedOnRequest)
        #expect(libidn2.latestVersion == "2.3.7")
    }

    @Test func parsesCasks() throws {
        let packages = try BrewParser.parseInfo(Self.infoJSON)
        let firefox = try #require(packages.first { $0.name == "firefox" })
        #expect(firefox.kind == .cask)
        #expect(firefox.displayName == "Mozilla Firefox")
        #expect(firefox.installedVersion == "139.0")
        #expect(firefox.latestVersion == "140.0")
        #expect(firefox.autoUpdates)
        #expect(firefox.dependencies.isEmpty, "macOS requirements aren't package dependencies")
        #expect(firefox.appPaths == ["/Applications/Firefox.app"])

        let tool = try #require(packages.first { $0.name == "some-tool" })
        #expect(tool.dependencies == [
            PackageRef(kind: .formula, name: "python@3.13"),
            PackageRef(kind: .cask, name: "xquartz"),
        ])
        #expect(tool.appPaths == ["/Applications/Renamed.app"])
    }

    @Test func parsesAndMergesOutdated() throws {
        let outdatedJSON = Data(#"""
        {
          "formulae": [
            { "name": "wget", "installed_versions": ["1.25.0"], "current_version": "1.25.0_1", "pinned": true, "pinned_version": "1.25.0" }
          ],
          "casks": [
            { "name": "firefox", "installed_versions": ["139.0"], "current_version": "140.0" }
          ]
        }
        """#.utf8)
        let entries = try BrewParser.parseOutdated(outdatedJSON)
        #expect(entries.count == 2)
        #expect(entries[1].ref == PackageRef(kind: .cask, name: "firefox"))

        var packages = try BrewParser.parseInfo(Self.infoJSON)
        // `brew info` may claim something is outdated that `brew outdated` doesn't list.
        packages[1].isOutdated = true
        let merged = BrewParser.merge(packages, outdated: entries)

        let wget = try #require(merged.first { $0.name == "wget" })
        #expect(wget.isOutdated)
        #expect(wget.isPinned)
        #expect(wget.latestVersion == "1.25.0_1")
        #expect(merged.first { $0.name == "firefox" }?.isOutdated == true)
        #expect(merged.first { $0.name == "libidn2" }?.isOutdated == false)
    }

    @Test func emptyInstallation() throws {
        let packages = try BrewParser.parseInfo(Data(#"{"formulae": [], "casks": []}"#.utf8))
        #expect(packages.isEmpty)
    }

    @Test func notInstalledPackage() throws {
        let json = Data(#"""
        {"formulae": [{"name": "jq", "versions": {"stable": "1.8.1"}, "installed": [], "dependencies": ["oniguruma"]}], "casks": []}
        """#.utf8)
        let jq = try #require(try BrewParser.parseInfo(json).first)
        #expect(!jq.isInstalled)
        #expect(jq.latestVersion == "1.8.1")
        #expect(jq.dependencies.map(\.name) == ["oniguruma"])
    }

    @Test func parsesRealBrewOutputIfAvailable() async throws {
        guard let brew = BrewService.locateBrew() else { return }
        let service = BrewService(brewURL: brew)
        let packages = try await service.installedPackages(includeAutoUpdatingCasks: false)
        let allInstalled = packages.allSatisfy { $0.isInstalled }
        #expect(allInstalled)
    }
}
