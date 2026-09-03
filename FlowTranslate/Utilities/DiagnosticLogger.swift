import AppKit
import Foundation

final class DiagnosticLogger: @unchecked Sendable {
    static let shared = DiagnosticLogger()

    private let lock = NSLock()
    private let maximumBytes: UInt64 = 2 * 1_024 * 1_024
    private let logURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appending(path: "PallasOwl Translator", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = directory.appending(path: "diagnostics.log")
    }

    func record(session: UUID, event: String, details: [String: String] = [:], at date: Date = Date()) {
        let timestamp = ISO8601DateFormatter().string(from: date)
        let suffix = details.sorted { $0.key < $1.key }.map { key, value in
            "\(clean(key))=\(clean(value))"
        }.joined(separator: " ")
        let line = "\(timestamp) screenshot=\(session.uuidString) event=\(clean(event))\(suffix.isEmpty ? "" : " " + suffix)\n"
        guard let data = line.data(using: .utf8) else { return }

        lock.lock()
        defer { lock.unlock() }
        rotateIfNeeded(adding: UInt64(data.count))
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {}
    }

    @MainActor
    func revealInFinder() {
        ensureFileExists()
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? Data().write(to: logURL, options: .atomic)
    }

    private func ensureFileExists() {
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
    }

    private func rotateIfNeeded(adding bytes: UInt64) {
        let current = ((try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size]) as? NSNumber)?.uint64Value ?? 0
        guard current + bytes > maximumBytes else { return }
        let previous = logURL.deletingLastPathComponent().appending(path: "diagnostics.previous.log")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: logURL, to: previous)
    }

    private func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }
}
