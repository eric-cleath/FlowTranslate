import Foundation

struct MediaSubtitleSegment: Identifiable, Sendable {
    let id = UUID()
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

enum MediaProcessingError: LocalizedError {
    case toolMissing(String)
    case processFailed(String)
    case noSpeech
    case unreadableOutput

    var errorDescription: String? {
        switch self {
        case .toolMissing(let name): "未找到 \(name)，请在“设置 → 媒体处理”中检查程序位置。"
        case .processFailed(let message): message.isEmpty ? "媒体处理失败。" : message
        case .noSpeech: "没有提取到字幕或可识别的语音。"
        case .unreadableOutput: "无法读取转写结果。"
        }
    }
}

struct MediaTranscriptionResult: Sendable {
    let segments: [MediaSubtitleSegment]
    let source: String
    var text: String { segments.map(\.text).joined(separator: "\n") }
}

struct MediaProcessingService: Sendable {
    func transcribe(
        url: URL,
        whisperPath: String,
        model: String,
        languageCode: String,
        preferEmbeddedSubtitles: Bool
    ) async throws -> MediaTranscriptionResult {
        if preferEmbeddedSubtitles, let embedded = try? await extractEmbeddedSubtitle(from: url), !embedded.isEmpty {
            return .init(segments: embedded, source: "视频内嵌字幕")
        }
        let whisperURL = URL(fileURLWithPath: NSString(string: whisperPath).expandingTildeInPath)
        guard FileManager.default.isExecutableFile(atPath: whisperURL.path) else {
            throw MediaProcessingError.toolMissing("Whisper")
        }
        let outputDirectory = FileManager.default.temporaryDirectory.appending(path: "PallasOwl-Media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        var arguments = [url.path, "--model", model, "--output_dir", outputDirectory.path, "--output_format", "srt", "--verbose", "False"]
        if languageCode != "auto" { arguments += ["--language", whisperLanguageCode(languageCode)] }
        _ = try await run(whisperURL, arguments: arguments)
        let candidates = (try? FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil)) ?? []
        guard let srt = candidates.first(where: { $0.pathExtension.lowercased() == "srt" }),
              let content = try? String(contentsOf: srt, encoding: .utf8) else { throw MediaProcessingError.unreadableOutput }
        let segments = parseSRT(content)
        guard !segments.isEmpty else { throw MediaProcessingError.noSpeech }
        return .init(segments: segments, source: "Whisper · \(model)")
    }

    func mediaDuration(url: URL) async -> TimeInterval? {
        guard let ffprobe = executable(named: "ffprobe") else { return nil }
        guard let output = try? await run(ffprobe, arguments: ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", url.path]) else { return nil }
        return TimeInterval(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func extractEmbeddedSubtitle(from url: URL) async throws -> [MediaSubtitleSegment]? {
        guard let ffprobe = executable(named: "ffprobe"), let ffmpeg = executable(named: "ffmpeg") else { return nil }
        let probe = try await run(ffprobe, arguments: ["-v", "error", "-select_streams", "s", "-show_entries", "stream=index", "-of", "csv=p=0", url.path])
        guard !probe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let output = FileManager.default.temporaryDirectory.appending(path: "PallasOwl-Subtitle-\(UUID().uuidString).srt")
        defer { try? FileManager.default.removeItem(at: output) }
        _ = try await run(ffmpeg, arguments: ["-y", "-v", "error", "-i", url.path, "-map", "0:s:0", output.path])
        guard let text = try? String(contentsOf: output, encoding: .utf8) else { return nil }
        let segments = parseSRT(text)
        return segments.isEmpty ? nil : segments
    }

    private func executable(named name: String) -> URL? {
        ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func run(_ executable: URL, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            process.environment = environment
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0 else {
                let message = output.split(separator: "\n").suffix(8).joined(separator: "\n")
                throw MediaProcessingError.processFailed(message)
            }
            return output
        }.value
    }

    private func parseSRT(_ content: String) -> [MediaSubtitleSegment] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timelineIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let times = lines[timelineIndex].components(separatedBy: "-->")
            guard times.count == 2, let start = parseTimestamp(times[0]), let end = parseTimestamp(times[1]) else { return nil }
            let text = lines.dropFirst(timelineIndex + 1).joined(separator: " ")
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return MediaSubtitleSegment(start: start, end: end, text: text)
        }
    }

    private func parseTimestamp(_ raw: String) -> TimeInterval? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = value.split(separator: ":").compactMap(Double.init)
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    private func whisperLanguageCode(_ code: String) -> String {
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return base == "zh" ? "zh" : base
    }
}
