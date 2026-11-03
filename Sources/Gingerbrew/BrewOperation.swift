import Foundation
import GingerbrewCore
import Observation

/// A running (or finished) install/upgrade/uninstall, with its live output.
@MainActor
@Observable
final class BrewOperation: Identifiable {
    enum State: Equatable {
        case running
        case succeeded
        case failed(status: Int32)
        case cancelled
    }

    let id = UUID()
    let action: PackageAction
    let displayName: String?
    private(set) var state: State = .running
    private(set) var lines: [String] = []
    var task: Task<Void, Never>?

    private static let maxLines = 2_000

    init(action: PackageAction, displayName: String?) {
        self.action = action
        self.displayName = displayName
    }

    var isRunning: Bool { state == .running }
    var ref: PackageRef? { action.ref }
    var output: String { lines.joined(separator: "\n") }
    var lastLine: String? { lines.last }

    var title: String {
        switch state {
        case .running: action.progressTitle(displayName: displayName)
        case .succeeded: action.completedTitle(displayName: displayName)
        case .failed: "Couldn't finish: \(action.progressTitle(displayName: displayName).lowercasedFirst)"
        case .cancelled: "Cancelled"
        }
    }

    /// The most useful line of output to explain a failure.
    var failureSummary: String? {
        lines.last { $0.hasPrefix("Error:") }?
            .replacingOccurrences(of: "Error: ", with: "")
            ?? lines.last
    }

    func append(_ line: String) {
        lines.append(line)
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
    }

    func finish(_ state: State) {
        self.state = state
    }

    func cancel() {
        task?.cancel()
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
