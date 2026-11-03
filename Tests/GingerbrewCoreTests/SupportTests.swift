import Foundation
import Testing
@testable import GingerbrewCore

@Suite("Support")
struct SupportTests {
    @Test func actionArguments() {
        let wget = PackageRef(kind: .formula, name: "wget")
        let firefox = PackageRef(kind: .cask, name: "firefox")
        #expect(PackageAction.install(wget).arguments == ["install", "--formula", "wget"])
        #expect(PackageAction.upgrade(wget).arguments == ["upgrade", "--formula", "wget"])
        #expect(PackageAction.upgrade(firefox).arguments == ["upgrade", "--cask", "--greedy", "firefox"])
        #expect(PackageAction.upgradeAll(greedy: false).arguments == ["upgrade"])
        #expect(PackageAction.upgradeAll(greedy: true).arguments == ["upgrade", "--greedy"])
        #expect(PackageAction.uninstall(firefox).arguments == ["uninstall", "--cask", "firefox"])
        #expect(PackageAction.uninstallCompletely(firefox).arguments == ["uninstall", "--cask", "--zap", "firefox"])
        #expect(PackageAction.uninstallCompletely(wget).arguments == ["uninstall", "--formula", "--force", "wget"])
    }

    @Test func lineSplitter() {
        var splitter = LineSplitter()
        #expect(splitter.append(Data("==> Down".utf8)).isEmpty, "partial lines wait for a newline")
        #expect(splitter.append(Data("loading\n\u{1B}[1;32mdone\u{1B}[0m\n".utf8)) == ["==> Downloading", "done"])
        #expect(splitter.append(Data("##   10%\r####  50%\r###### 100%\n".utf8)) == ["###### 100%"])
        #expect(splitter.append(Data("\n   \n".utf8)).isEmpty, "blank lines are dropped")
        #expect(splitter.append(Data("tail".utf8)).isEmpty)
        #expect(splitter.flush() == "tail")
        #expect(splitter.flush() == nil)
    }

    @Test func processStreaming() async throws {
        let lines = LockedLines()
        let status = try await ProcessRunner.stream(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo one; echo two >&2; printf three; exit 3"]
        ) { lines.append($0) }
        #expect(status == 3)
        #expect(lines.values == ["one", "two", "three"])
    }

    @Test func processRunCollectsLargeOutput() async throws {
        // Larger than a pipe buffer, to make sure nothing deadlocks.
        let output = try await ProcessRunner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "yes gingerbrew | head -n 50000; echo oops >&2"])
        #expect(output.succeeded)
        #expect(output.stdout.count == 50_000 * 11)
        #expect(output.stderr == "oops\n")
    }

    @Test func developerFromCopyright() {
        #expect(DeveloperName.from(copyright: "Copyright © 2015-2024 Mozilla Corporation. All rights reserved.") == "Mozilla Corporation")
        #expect(DeveloperName.from(copyright: "© 2023 Anoop M D") == "Anoop M D")
        #expect(DeveloperName.from(copyright: "(c) 2020 - present, Example Inc.") == "Example Inc")
        #expect(DeveloperName.from(copyright: "Copyright 2024") == nil)
        #expect(DeveloperName.from(copyright: nil) == nil)
    }

    @Test func developerFromHomepage() {
        #expect(DeveloperName.from(homepage: URL(string: "https://github.com/BurntSushi/ripgrep")) == "BurntSushi")
        #expect(DeveloperName.from(homepage: URL(string: "https://www.mozilla.org/firefox/")) == "mozilla.org")
        #expect(DeveloperName.from(homepage: URL(string: "https://sharkdp.github.io/bat")) == "sharkdp")
        #expect(DeveloperName.from(homepage: URL(string: "https://git.sr.ht/~sircmpwn/aerc")) == "sircmpwn")
        #expect(DeveloperName.from(homepage: nil) == nil)
    }

    @Test func packageMatchesDependency() {
        let package = Package(ref: PackageRef(kind: .formula, name: "foo"), fullName: "user/tap/foo")
        #expect(package.matches(PackageRef(kind: .formula, name: "foo")))
        #expect(package.matches(PackageRef(kind: .formula, name: "user/tap/foo")))
        #expect(!package.matches(PackageRef(kind: .cask, name: "foo")))
        #expect(PackageRef(kind: .formula, name: "user/tap/foo").shortName == "foo")
    }
}

final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ line: String) { lock.withLock { storage.append(line) } }
    var values: [String] { lock.withLock { storage } }
}
