import Foundation
import Testing
@testable import GingerbrewCore

@Suite("Search")
struct SearchTests {
    @Test func rankingOrder() {
        func score(_ name: String, _ display: String? = nil, _ summary: String? = nil, q: String) -> Int? {
            SearchRanker.score(name: name, displayName: display ?? name, summary: summary, query: q)
        }
        let exact = score("git", q: "git")!
        let prefix = score("git-lfs", q: "git")!
        let word = score("lazy-git-ui", q: "git")!
        let contains = score("legit", q: "git")!
        let summary = score("tig", nil, "Text interface for git repositories", q: "git")!
        #expect(exact > prefix)
        #expect(prefix > word)
        #expect(word > contains)
        #expect(contains > summary)
        #expect(score("wget", q: "zzz") == nil)
        #expect(score("Firefox", q: "  FIRE ") != nil, "case and whitespace insensitive")
    }

    @Test func matchesDisplayName() {
        let score = SearchRanker.score(
            name: "visual-studio-code", displayName: "Microsoft Visual Studio Code",
            summary: nil, query: "studio")
        #expect(score != nil)
    }

    @Test func multiWordSummaryMatch() {
        let score = SearchRanker.score(
            name: "rg", displayName: "rg", summary: "Search tool like grep and The Silver Searcher",
            query: "grep search")
        #expect(score != nil)
    }

    @Test func rankSortsAndFilters() {
        let names = ["node", "nodenv", "nvm", "anode", "deno"]
        let ranked = SearchRanker.rank(names, query: "node", name: { $0 }, displayName: { $0 }, summary: { _ in nil })
        #expect(ranked == ["node", "nodenv", "anode"])
    }

    @Test func decodesAPIAndSearchesIndex() async throws {
        let formulae = Data(#"""
        [{"name": "wget", "desc": "Internet file retriever", "homepage": "https://gnu.org", "versions": {"stable": "1.25.0"}},
         {"name": "oldthing", "desc": "Gone", "versions": {"stable": "1"}, "disabled": true}]
        """#.utf8)
        let casks = Data(#"""
        [{"token": "firefox", "name": ["Mozilla Firefox"], "desc": "Web browser", "version": "140.0"}]
        """#.utf8)
        let entries = try SearchIndex.decodeFormulae(formulae) + SearchIndex.decodeCasks(casks)
        #expect(entries.count == 2, "disabled packages are skipped")
        #expect(entries.last?.displayName == "Mozilla Firefox")
        #expect(entries.first?.version == "1.25.0")

        let package = Package(entry: entries[1])
        #expect(!package.isInstalled)
        #expect(package.kind == .cask)
        #expect(package.latestVersion == "140.0")
    }
}
