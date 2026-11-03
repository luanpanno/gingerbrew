import Foundation

/// Homebrew doesn't record who makes a package, so Gingerbrew infers it.
public enum DeveloperName {
    /// From an app bundle's `NSHumanReadableCopyright`, e.g.
    /// "Copyright © 2015-2024 Mozilla Corporation. All rights reserved." → "Mozilla Corporation".
    public static func from(copyright: String?) -> String? {
        guard var text = copyright?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        let patterns = [
            "(?i)all rights reserved\\.?",
            "(?i)copyright",
            "(?i)\\(c\\)",
            "©",
            "\\b(19|20)\\d{2}\\s*[-–—]\\s*((19|20)\\d{2}|present)\\b",
            "\\b(19|20)\\d{2}\\b",
        ]
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        // Keep the first sentence/clause and tidy punctuation.
        if let first = text.split(whereSeparator: { $0 == "\n" }).first {
            text = String(first)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-–—").union(.whitespaces))
        if text.hasPrefix("by ") { text.removeFirst(3) }
        return text.count >= 2 ? text : nil
    }

    /// From a homepage: the owner for code hosts, otherwise the site's domain.
    /// "https://github.com/BurntSushi/ripgrep" → "BurntSushi", "https://www.mozilla.org/" → "mozilla.org".
    public static func from(homepage: URL?) -> String? {
        guard let homepage, var host = homepage.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let codeHosts = ["github.com", "gitlab.com", "codeberg.org", "sr.ht", "git.sr.ht", "bitbucket.org"]
        if codeHosts.contains(host) {
            let owner = homepage.pathComponents.dropFirst().first
            if let owner, !owner.isEmpty { return owner.hasPrefix("~") ? String(owner.dropFirst()) : owner }
        }
        if host.hasSuffix(".github.io") { return String(host.dropLast(".github.io".count)) }
        return host
    }
}
