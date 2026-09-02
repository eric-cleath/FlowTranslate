import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum MediaExportFormat: String, CaseIterable, Identifiable {
    case markdown = "Obsidian Markdown"
    case text = "纯文本"
    case srt = "SRT 字幕"
    case vtt = "VTT 字幕"
    var id: Self { self }
    var fileExtension: String { switch self { case .markdown: "md"; case .text: "txt"; case .srt: "srt"; case .vtt: "vtt" } }
}

@MainActor @Observable
final class MediaProcessingModel {
    var fileURL: URL?
    var sourceLanguage = Language.supported[0]
    var targetLanguage = Language.supported.first(where: { $0.code == "zh-Hans" }) ?? Language.supported[1]
    var segments: [MediaSubtitleSegment] = []
    var transcript = ""
    var translation = ""
    var summary = ""
    var status = "请选择视频或音频文件"
    var sourceDescription = ""
    var errorMessage: String?
    var isWorking = false
    var progress = 0.0
    var exportFormat = MediaExportFormat.markdown
    var duration: TimeInterval?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let service = MediaProcessingService()

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["mp4", "mov", "m4v", "mkv", "webm", "mp3", "m4a", "wav", "aac", "flac", "ogg"]
            .compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        task?.cancel()
        fileURL = url; segments = []; transcript = ""; translation = ""; summary = ""
        sourceDescription = ""; errorMessage = nil; progress = 0; status = "文件已载入，可以开始转写"
        Task { duration = await service.mediaDuration(url: url) }
    }

    func transcribe() {
        guard let fileURL else { return }
        task?.cancel(); isWorking = true; progress = 0.08; errorMessage = nil
        status = "正在检查内嵌字幕…"
        let whisperPath = UserDefaults.standard.string(forKey: "mediaWhisperPath") ?? "/opt/homebrew/bin/whisper"
        let whisperModel = UserDefaults.standard.string(forKey: "mediaWhisperModel") ?? "small"
        let preferEmbedded = UserDefaults.standard.object(forKey: "mediaPreferEmbeddedSubtitles") as? Bool ?? true
        task = Task {
            do {
                progress = 0.16
                status = preferEmbedded ? "优先提取内嵌字幕；没有字幕时将调用 Whisper…" : "正在调用 Whisper 转写…"
                let result = try await service.transcribe(url: fileURL, whisperPath: whisperPath, model: whisperModel,
                                                          languageCode: sourceLanguage.code, preferEmbeddedSubtitles: preferEmbedded)
                guard !Task.isCancelled else { return }
                segments = result.segments; transcript = result.text; sourceDescription = result.source
                translation = ""; summary = ""; progress = 1; status = "转写完成 · \(result.source) · \(result.segments.count) 段"
                UsageMetrics.increment(.mediaTranscription)
            } catch is CancellationError { status = "已取消" }
            catch { errorMessage = error.localizedDescription; status = "处理失败"; progress = 0 }
            isWorking = false
        }
    }

    func translate(using handler: @escaping (String, Language, Language) async throws -> String) {
        guard !transcript.isEmpty else { return }
        task?.cancel(); isWorking = true; errorMessage = nil; translation = ""; progress = 0.05; status = "正在翻译转写内容…"
        let chunks = chunk(transcript, limit: 4_500)
        task = Task {
            do {
                var translated: [String] = []
                for (index, value) in chunks.enumerated() {
                    guard !Task.isCancelled else { throw CancellationError() }
                    status = "正在翻译第 \(index + 1)/\(chunks.count) 段…"
                    translated.append(try await handler(value, sourceLanguage, targetLanguage))
                    progress = Double(index + 1) / Double(chunks.count)
                }
                translation = translated.joined(separator: "\n\n")
                status = "翻译完成"; UsageMetrics.increment(.mediaTranslation)
            } catch is CancellationError { status = "已取消" }
            catch { errorMessage = error.localizedDescription; status = "翻译失败" }
            isWorking = false
        }
    }

    func summarize(using handler: @escaping (String, Language) async throws -> String) {
        let text = translation.isEmpty ? transcript : translation
        guard !text.isEmpty else { return }
        task?.cancel(); isWorking = true; errorMessage = nil; summary = ""; progress = 0.05; status = "正在生成摘要…"
        let chunks = chunk(text, limit: 9_000)
        task = Task {
            do {
                if chunks.count == 1 {
                    summary = try await handler(text, targetLanguage)
                } else {
                    var partialSummaries: [String] = []
                    for (index, value) in chunks.enumerated() {
                        guard !Task.isCancelled else { throw CancellationError() }
                        status = "正在总结第 \(index + 1)/\(chunks.count) 段…"
                        partialSummaries.append(try await handler(value, targetLanguage))
                        progress = 0.8 * Double(index + 1) / Double(chunks.count)
                    }
                    status = "正在合并分段摘要…"
                    summary = try await handler(partialSummaries.joined(separator: "\n\n"), targetLanguage)
                }
                progress = 1; status = "摘要生成完成"; UsageMetrics.increment(.mediaSummary)
            } catch is CancellationError { status = "已取消" }
            catch { errorMessage = error.localizedDescription; status = "摘要生成失败" }
            isWorking = false
        }
    }

    func cancel() { task?.cancel(); task = nil; isWorking = false; status = "已取消" }

    func export() {
        guard !transcript.isEmpty else { return }
        let panel = NSSavePanel()
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? "媒体转写"
        panel.nameFieldStringValue = "\(base)-转写.\(exportFormat.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: exportFormat.fileExtension) ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try exportContent().write(to: url, atomically: true, encoding: .utf8); status = "已导出：\(url.lastPathComponent)" }
        catch { errorMessage = "导出失败：\(error.localizedDescription)" }
    }

    private func exportContent() -> String {
        switch exportFormat {
        case .srt: return subtitle(vtt: false)
        case .vtt: return "WEBVTT\n\n" + subtitle(vtt: true)
        case .text:
            return [summary.isEmpty ? nil : "摘要\n\(summary)", "完整转写\n\(transcript)", translation.isEmpty ? nil : "翻译结果\n\(translation)"].compactMap { $0 }.joined(separator: "\n\n")
        case .markdown:
            let title = fileURL?.deletingPathExtension().lastPathComponent ?? "媒体转写"
            var value = "# \(title)\n\n"
            if !summary.isEmpty { value += "## 内容摘要\n\n\(summary)\n\n" }
            value += "## 完整转写\n\n"
            for segment in segments { value += "- **[\(clock(segment.start))]** \(segment.text)\n" }
            if !translation.isEmpty { value += "\n## 翻译结果\n\n\(translation)\n" }
            return value
        }
    }

    private func subtitle(vtt: Bool) -> String {
        segments.enumerated().map { index, segment in
            let separator = vtt ? "." : ","
            let timeline = "\(timestamp(segment.start, separator: separator)) --> \(timestamp(segment.end, separator: separator))"
            return vtt ? "\(timeline)\n\(segment.text)" : "\(index + 1)\n\(timeline)\n\(segment.text)"
        }.joined(separator: "\n\n")
    }

    private func timestamp(_ time: TimeInterval, separator: String) -> String {
        let milliseconds = Int((time * 1000).rounded())
        return String(format: "%02d:%02d:%02d%@%03d", milliseconds / 3_600_000, (milliseconds / 60_000) % 60,
                      (milliseconds / 1000) % 60, separator, milliseconds % 1000)
    }

    private func clock(_ time: TimeInterval) -> String { String(format: "%02d:%02d:%02d", Int(time) / 3600, (Int(time) / 60) % 60, Int(time) % 60) }

    private func chunk(_ text: String, limit: Int) -> [String] {
        var values: [String] = [], current = ""
        for paragraph in text.components(separatedBy: "\n\n") {
            if current.count + paragraph.count + 2 > limit, !current.isEmpty { values.append(current); current = "" }
            if paragraph.count > limit {
                if !current.isEmpty { values.append(current); current = "" }
                var start = paragraph.startIndex
                while start < paragraph.endIndex {
                    let end = paragraph.index(start, offsetBy: limit, limitedBy: paragraph.endIndex) ?? paragraph.endIndex
                    values.append(String(paragraph[start..<end])); start = end
                }
            } else { current += (current.isEmpty ? "" : "\n\n") + paragraph }
        }
        if !current.isEmpty { values.append(current) }
        return values
    }
}

struct MediaProcessingView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = state.mediaProcessing
        VStack(spacing: 12) {
            HStack {
                Button { model.chooseFile() } label: { Label("选择媒体", systemImage: "film.stack") }.buttonStyle(.borderedProminent)
                Text("支持 MP4、MOV、M4V、MKV、WebM、MP3、M4A、WAV、AAC、FLAC、OGG")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            mediaCard
            HStack {
                languagePicker("输入语言", selection: $model.sourceLanguage, allowsAuto: true)
                Image(systemName: "arrow.right")
                languagePicker("目标语言", selection: $model.targetLanguage, allowsAuto: false)
                Spacer()
                Button(model.isWorking ? "停止" : "开始转写") { model.isWorking ? model.cancel() : model.transcribe() }
                    .buttonStyle(.borderedProminent).disabled(model.fileURL == nil)
            }
            HSplitView {
                textArea("转写原文", model.transcript, placeholder: "字幕或 Whisper 转写结果会显示在这里")
                VStack(spacing: 10) {
                    textArea("翻译结果", model.translation, placeholder: "可在转写完成后进行翻译")
                    textArea("内容摘要", model.summary, placeholder: "可根据原文或译文生成摘要")
                }
            }
            if model.isWorking || model.progress > 0 {
                VStack(spacing: 4) { ProgressView(value: model.progress); HStack { Text(model.status); Spacer(); Text("\(Int(model.progress * 100))%") }.font(.caption).foregroundStyle(.secondary) }
            } else { Text(model.status).font(.caption).foregroundStyle(.secondary) }
            if let error = model.errorMessage { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Button {
                    UserDefaults.standard.set("媒体处理", forKey: "requestedSettingsCategory")
                    openSettings()
                } label: { Image(systemName: "gearshape").font(.system(size: 16, weight: .semibold)) }
                    .buttonStyle(.plain).help("打开媒体处理设置")
                Text("· 当前服务：\(state.documentCurrentServiceName)")
                    .foregroundStyle(.secondary)
                Button("翻译") { model.translate { try await state.translateDocumentChunk($0, source: $1, target: $2) } }
                    .disabled(model.transcript.isEmpty || model.isWorking)
                Button("生成摘要") { model.summarize { try await state.summarizeMediaText($0, target: $1) } }
                    .disabled(model.transcript.isEmpty || model.isWorking)
                Spacer()
                Picker("导出格式", selection: $model.exportFormat) { ForEach(MediaExportFormat.allCases) { Text($0.rawValue).tag($0) } }
                    .labelsHidden().frame(width: 165)
                Button("导出结果") { model.export() }.disabled(model.transcript.isEmpty || model.isWorking)
            }.font(.callout)
        }.padding(.horizontal).padding(.bottom)
    }

    private var mediaCard: some View {
        let model = state.mediaProcessing
        return HStack(spacing: 14) {
            Image(systemName: model.fileURL == nil ? "play.rectangle.on.rectangle" : "film.fill")
                .font(.system(size: 30)).foregroundStyle(.blue).frame(width: 68, height: 58)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(model.fileURL?.lastPathComponent ?? "尚未选择媒体文件").fontWeight(.semibold).lineLimit(1)
                if let duration = model.duration { Text("时长：\(durationText(duration))").font(.caption).foregroundStyle(.secondary) }
                else { Text("优先提取已有字幕；没有字幕时使用本地 Whisper 转写").font(.caption).foregroundStyle(.secondary) }
                if !model.sourceDescription.isEmpty { Label(model.sourceDescription, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
            }
            Spacer()
        }.padding(10).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }

    private func textArea(_ title: String, _ text: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            ScrollView {
                Text(text.isEmpty ? placeholder : text).foregroundStyle(text.isEmpty ? .tertiary : .primary)
                    .font(.system(size: state.editorFontSize)).lineSpacing(state.editorLineSpacing)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
            }.background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }.frame(minWidth: 300, minHeight: 145)
    }

    private func languagePicker(_ title: String, selection: Binding<Language>, allowsAuto: Bool) -> some View {
        Picker(title, selection: selection) { ForEach(Language.supported.filter { allowsAuto || $0.code != "auto" }) { Text($0.name).tag($0) } }.frame(width: 155)
    }

    private func durationText(_ seconds: TimeInterval) -> String { String(format: "%02d:%02d:%02d", Int(seconds) / 3600, (Int(seconds) / 60) % 60, Int(seconds) % 60) }
}
