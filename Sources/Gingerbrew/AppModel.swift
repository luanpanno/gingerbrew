import AppKit
import Foundation
import GingerbrewCore
import Observation
import SwiftUI

/// App state: installed packages, search, navigation and the running brew operation.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading
        case ready
        case brewMissing
    }

    let settings = AppSettings()

    private(set) var phase: Phase = .loading
    private(set) var service: BrewService?
    private(set) var brewVersion: String?

    // Installed packages
    private(set) var installed: [Package] = []
    private(set) var hasLoadedInstalled = false
    private(set) var isRefreshing = false
    private(set) var isCheckingForUpdates = false
    var errorMessage: String?

    // Search
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    private(set) var recommendations: [IndexEntry] = []
    private(set) var isSearching = false
    private(set) var isIndexLoading = false
    private(set) var indexUpdatedAt: Date?
    private(set) var indexError: String?

    // Navigation and details
    private(set) var path: [PackageRef] = []
    private(set) var details: [PackageRef: Package] = [:]
    private(set) var loadingDetails: Set<PackageRef> = []
    private(set) var detailErrors: [PackageRef: String] = [:]
    private var fullyLoaded: Set<PackageRef> = []

    // Operations
    private(set) var operation: BrewOperation?

    /// Whether the menu bar panel is currently open.
    private(set) var isPanelVisible = false

    private let index = SearchIndex(cacheURL: SearchIndex.defaultCacheURL)
    private var searchTask: Task<Void, Never>?
    private var schedulerTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var notifiedOutdated: Set<PackageRef> = []

    init() {
        Task { await start() }
    }

    // MARK: Derived state

    var outdated: [Package] { installed.filter(\.isOutdated) }

    var isSearchActive: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var filteredInstalled: [Package] {
        SearchRanker.rank(
            installed, query: query,
            name: \.name, displayName: \.displayName, summary: \.summary)
    }

    func package(for ref: PackageRef) -> Package? {
        installed.first { $0.matches(ref) } ?? details[ref]
    }

    func installedPackage(for ref: PackageRef) -> Package? {
        installed.first { $0.matches(ref) }
    }

    /// Installed packages that directly depend on `package`.
    func usedBy(_ package: Package) -> [Package] {
        installed.filter { other in other.dependencies.contains { package.matches($0) } }
    }

    // MARK: Lifecycle

    func start() async {
        guard let brewURL = BrewService.locateBrew() else {
            phase = .brewMissing
            return
        }
        let askpass = Bundle.main.url(forResource: "askpass", withExtension: "sh")
        let service = BrewService(brewURL: brewURL, askpassURL: askpass)
        self.service = service
        phase = .ready
        await refresh()
        notifiedOutdated = Set(outdated.map(\.ref))
        if settings.notificationsEnabled { Notifier.requestAuthorization() }
        Task { brewVersion = await service.version() }
        Task { await prepareIndex() }
        startScheduler()
    }

    func panelDidOpen() {
        isPanelVisible = true
        if phase == .ready, !isRefreshing, operation?.isRunning != true {
            Task { await refresh() }
        }
    }

    func panelDidClose() {
        isPanelVisible = false
    }

    // MARK: Installed packages

    func refresh() async {
        guard let service, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            installed = try await service.installedPackages(
                includeAutoUpdatingCasks: settings.includeAutoUpdatingCasks)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoadedInstalled = true
    }

    /// `brew update`, then reload. Background checks notify about newly available updates.
    func checkForUpdates(userInitiated: Bool) async {
        guard let service, !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        do {
            try await service.update()
        } catch where userInitiated {
            errorMessage = "Couldn't update Homebrew: \(error.localizedDescription)"
        } catch {}
        await refresh()
        settings.lastUpdateCheck = Date()

        let current = Set(outdated.map(\.ref))
        let fresh = outdated.filter { !notifiedOutdated.contains($0.ref) }
        if !userInitiated, !fresh.isEmpty, settings.notificationsEnabled {
            let names = fresh.prefix(3).map(\.displayName).joined(separator: ", ")
            let more = fresh.count > 3 ? " and \(fresh.count - 3) more" : ""
            Notifier.post(
                title: fresh.count == 1 ? "1 update available" : "\(fresh.count) updates available",
                body: names + more)
        }
        notifiedOutdated = current
    }

    /// Re-evaluates every 15 minutes, so interval changes apply without restarting.
    private func startScheduler() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let hours = settings.checkIntervalHours
                if hours > 0 {
                    let due = (settings.lastUpdateCheck ?? .distantPast)
                        .addingTimeInterval(Double(hours) * 3600)
                    if due <= Date(), operation?.isRunning != true {
                        await checkForUpdates(userInitiated: false)
                    }
                }
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
    }

    func retryLocatingBrew() {
        phase = .loading
        Task { await start() }
    }

    // MARK: Search

    func prepareIndex(force: Bool = false) async {
        guard !isIndexLoading else { return }
        isIndexLoading = true
        defer { isIndexLoading = false }
        do {
            if force { try await index.refresh() } else { try await index.prepare() }
            indexError = nil
        } catch {
            indexError = error.localizedDescription
        }
        indexUpdatedAt = await index.updatedAt
        if isSearchActive { scheduleSearch() }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = query
        guard isSearchActive else {
            recommendations = []
            isSearching = false
            return
        }
        isSearching = true
        let excluded = Set(installed.map(\.ref))
        searchTask = Task { [index] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let results = await index.search(query, excluding: excluded, limit: 25)
            guard !Task.isCancelled else { return }
            recommendations = results
            isSearching = false
        }
    }

    // MARK: Navigation

    func open(_ ref: PackageRef) {
        withAnimation(.snappy(duration: 0.25)) { path.append(ref) }
    }

    func goBack() {
        guard !path.isEmpty else { return }
        withAnimation(.snappy(duration: 0.25)) { _ = path.removeLast() }
    }

    func loadDetail(_ ref: PackageRef) async {
        guard let service, installedPackage(for: ref) == nil, !fullyLoaded.contains(ref),
              !loadingDetails.contains(ref)
        else { return }
        if details[ref] == nil, let entry = await index.entry(for: ref) {
            details[ref] = Package(entry: entry)
        }
        loadingDetails.insert(ref)
        defer { loadingDetails.remove(ref) }
        do {
            if let package = try await service.info(ref) {
                details[ref] = package
                fullyLoaded.insert(ref)
                detailErrors[ref] = nil
            } else {
                detailErrors[ref] = "Homebrew has no information about \(ref.name)."
            }
        } catch {
            detailErrors[ref] = error.localizedDescription
        }
    }

    // MARK: Operations

    var canPerformActions: Bool { service != nil && operation?.isRunning != true }

    func perform(_ action: PackageAction) {
        guard let service, canPerformActions else { return }
        dismissTask?.cancel()
        var displayName: String?
        if let ref = action.ref, let package = package(for: ref) {
            displayName = package.displayName
            details[ref] = package  // Keep the detail page populated after an uninstall.
        }
        let operation = BrewOperation(action: action, displayName: displayName)
        self.operation = operation
        operation.task = Task { [weak self] in
            let (stream, continuation) = AsyncStream.makeStream(of: String.self)
            async let result = Self.execute(service, action, continuation)
            for await line in stream { operation.append(line) }
            switch await result {
            case _ where Task.isCancelled:
                operation.finish(.cancelled)
            case .success(0):
                operation.finish(.succeeded)
            case .success(let status):
                operation.finish(.failed(status: status))
            case .failure(let error):
                operation.append(error.localizedDescription)
                operation.finish(.failed(status: -1))
            }
            await self?.operationDidFinish(operation)
        }
    }

    private nonisolated static func execute(
        _ service: BrewService,
        _ action: PackageAction,
        _ continuation: AsyncStream<String>.Continuation
    ) async -> Result<Int32, Error> {
        defer { continuation.finish() }
        do {
            return .success(try await service.perform(action) { continuation.yield($0) })
        } catch {
            return .failure(error)
        }
    }

    private func operationDidFinish(_ operation: BrewOperation) async {
        if let ref = operation.ref { fullyLoaded.remove(ref) }
        await refresh()
        if let ref = operation.ref, installedPackage(for: ref) == nil {
            await loadDetail(ref)
        }
        notifiedOutdated = Set(outdated.map(\.ref))

        if settings.notificationsEnabled, !isPanelVisible {
            switch operation.state {
            case .succeeded: Notifier.post(title: operation.title, body: nil)
            case .failed: Notifier.post(title: operation.title, body: operation.failureSummary)
            default: break
            }
        }
        if operation.state == .succeeded {
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, self.operation === operation else { return }
                withAnimation { self.operation = nil }
            }
        }
    }

    func dismissOperation() {
        guard operation?.isRunning != true else { return }
        dismissTask?.cancel()
        withAnimation { operation = nil }
    }

    /// Keeps a finished operation on screen while the user reads its log.
    func keepOperationVisible() {
        dismissTask?.cancel()
    }
}
