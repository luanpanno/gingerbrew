import Foundation

/// A compact record of a package from Homebrew's public catalogue.
public struct IndexEntry: Codable, Hashable, Sendable, Identifiable {
    public let ref: PackageRef
    public let displayName: String
    public let summary: String?
    public let homepage: String?
    public let version: String?

    public init(ref: PackageRef, displayName: String, summary: String?, homepage: String?, version: String?) {
        self.ref = ref
        self.displayName = displayName
        self.summary = summary
        self.homepage = homepage
        self.version = version
    }

    public var id: String { ref.id }
}

/// Scores how well a package matches a search query. Higher is better; `nil` means no match.
public enum SearchRanker {
    public static func score(name: String, displayName: String, summary: String?, query: String) -> Int? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return 0 }
        let n = name.lowercased()
        let d = displayName.lowercased()
        let lengthPenalty = min(n.count, 100)

        if n == q || d == q { return 1000 }
        if n.hasPrefix(q) || d.hasPrefix(q) { return 800 - lengthPenalty }
        let words = d.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            + n.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(q) }) { return 600 - lengthPenalty }
        if n.contains(q) || d.contains(q) { return 400 - lengthPenalty }
        if let s = summary?.lowercased() {
            let terms = q.split(separator: " ")
            if terms.allSatisfy({ s.contains($0) }) { return 100 - lengthPenalty / 2 }
        }
        return nil
    }

    /// Filters and sorts `items` by relevance to `query`.
    public static func rank<T>(
        _ items: [T],
        query: String,
        name: (T) -> String,
        displayName: (T) -> String,
        summary: (T) -> String?
    ) -> [T] {
        items
            .compactMap { item in
                score(name: name(item), displayName: displayName(item), summary: summary(item), query: query)
                    .map { (item, $0) }
            }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1
                    ? lhs.1 > rhs.1
                    : name(lhs.0).localizedCaseInsensitiveCompare(name(rhs.0)) == .orderedAscending
            }
            .map(\.0)
    }
}

/// Searchable copy of the formulae.brew.sh catalogue, cached on disk.
///
/// The full API files are ~50 MB, so only the fields Gingerbrew needs are kept.
public actor SearchIndex {
    public static let formulaURL = URL(string: "https://formulae.brew.sh/api/formula.json")!
    public static let caskURL = URL(string: "https://formulae.brew.sh/api/cask.json")!

    private struct CacheFile: Codable {
        let updatedAt: Date
        let entries: [IndexEntry]
    }

    private let cacheURL: URL
    private let session: URLSession
    private var entries: [IndexEntry] = []
    public private(set) var updatedAt: Date?

    public init(cacheURL: URL, session: URLSession = .shared) {
        self.cacheURL = cacheURL
        self.session = session
    }

    public static var defaultCacheURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.luanpanno.gingerbrew", isDirectory: true)
            .appendingPathComponent("search-index.json")
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// Loads the disk cache, then downloads a fresh copy if it is missing or older than `maxAge`.
    public func prepare(maxAge: TimeInterval = 24 * 60 * 60) async throws {
        if entries.isEmpty { loadFromDisk() }
        let isStale = updatedAt.map { Date().timeIntervalSince($0) > maxAge } ?? true
        if isStale { try await refresh() }
    }

    public func refresh() async throws {
        async let formulaData = download(Self.formulaURL)
        async let caskData = download(Self.caskURL)
        let fresh = try Self.decodeFormulae(try await formulaData) + Self.decodeCasks(try await caskData)
        entries = fresh
        updatedAt = Date()
        saveToDisk()
    }

    public func search(_ query: String, excluding excluded: Set<PackageRef> = [], limit: Int = 30) -> [IndexEntry] {
        let candidates = entries.filter { !excluded.contains($0.ref) }
        return Array(SearchRanker.rank(
            candidates, query: query,
            name: \.ref.name, displayName: \.displayName, summary: \.summary
        ).prefix(limit))
    }

    public func entry(for ref: PackageRef) -> IndexEntry? {
        entries.first { $0.ref == ref }
    }

    // MARK: Private

    private func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: cacheURL),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data)
        else { return }
        entries = file.entries
        updatedAt = file.updatedAt
    }

    private func saveToDisk() {
        guard let updatedAt else { return }
        let file = CacheFile(updatedAt: updatedAt, entries: entries)
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(file).write(to: cacheURL, options: .atomic)
        } catch {
            // The cache is an optimisation; the next launch simply downloads again.
        }
    }

    // MARK: Decoding (internal for tests)

    private struct APIFormula: Decodable {
        struct Versions: Decodable { let stable: String? }
        let name: String
        let desc: String?
        let homepage: String?
        let versions: Versions?
        let disabled: Bool?
    }

    private struct APICask: Decodable {
        let token: String
        let name: [String]?
        let desc: String?
        let homepage: String?
        let version: String?
        let disabled: Bool?
    }

    static func decodeFormulae(_ data: Data) throws -> [IndexEntry] {
        try JSONDecoder().decode([APIFormula].self, from: data)
            .filter { $0.disabled != true }
            .map {
                IndexEntry(
                    ref: PackageRef(kind: .formula, name: $0.name),
                    displayName: $0.name, summary: $0.desc,
                    homepage: $0.homepage, version: $0.versions?.stable)
            }
    }

    static func decodeCasks(_ data: Data) throws -> [IndexEntry] {
        try JSONDecoder().decode([APICask].self, from: data)
            .filter { $0.disabled != true }
            .map {
                IndexEntry(
                    ref: PackageRef(kind: .cask, name: $0.token),
                    displayName: $0.name?.first ?? $0.token, summary: $0.desc,
                    homepage: $0.homepage, version: $0.version)
            }
    }
}
