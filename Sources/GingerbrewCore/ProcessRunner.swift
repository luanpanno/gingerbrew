import Foundation

public struct CommandOutput: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: String

    public var succeeded: Bool { status == 0 }
}

/// Runs a child process without a terminal: stdin is closed, so anything that
/// needs input must get it another way (for `sudo`, that's `SUDO_ASKPASS`).
public enum ProcessRunner {
    /// Runs to completion and collects stdout and stderr separately.
    public static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> CommandOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    // Drain both pipes concurrently so a full buffer can't deadlock the child.
                    let errorBox = DataBox()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        errorBox.data = err.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    let stdout = out.fileHandleForReading.readDataToEndOfFile()
                    group.wait()
                    process.waitUntilExit()
                    continuation.resume(returning: CommandOutput(
                        status: process.terminationStatus,
                        stdout: stdout,
                        stderr: String(decoding: errorBox.data, as: UTF8.self)
                    ))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Runs to completion, reporting combined stdout/stderr line by line as it arrives.
    /// Returns the exit status. Cancelling the task sends SIGINT, like Ctrl-C.
    public static func stream(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    var splitter = LineSplitter()
                    let handle = pipe.fileHandleForReading
                    while true {
                        let chunk = handle.availableData
                        if chunk.isEmpty { break }
                        splitter.append(chunk).forEach(onLine)
                    }
                    if let rest = splitter.flush() { onLine(rest) }
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                }
            }
        } onCancel: {
            if process.isRunning { process.interrupt() }
        }
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Splits a byte stream into display lines the way a terminal would show them:
/// carriage returns overwrite the line (progress bars) and ANSI escapes are dropped.
public struct LineSplitter {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = Self.clean(lineData) { lines.append(line) }
        }
        return lines
    }

    public mutating func flush() -> String? {
        defer { buffer.removeAll() }
        return buffer.isEmpty ? nil : Self.clean(buffer)
    }

    static func clean(_ data: Data) -> String? {
        var text = String(decoding: data, as: UTF8.self)
        text = text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        // Keep only what's left after the last carriage return that has text after it.
        let segments = text.split(separator: "\r", omittingEmptySubsequences: true)
        let visible = segments.last.map(String.init) ?? ""
        let trimmed = visible.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : visible
    }
}
