import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class DocumentTranslationModel {
    var fileURL: URL?
    var pastedImage: NSImage?
    var pastedImageName = ""
    var sourceLanguage = Language.supported[0]
    var targetLanguage = Language.supported[1]
    var outputStyle: DocumentOutputStyle = .translated
    var exportFormat: DocumentExportFormat = .markdown
    var sourceText = ""
    var sections: [DocumentTranslationSection] = []
    var progress = 0.0
    var status = ""
    var isWorking = false
    var activity = ""
    var errorMessage: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    var resultText: String {
        sections.map(\.translation).joined(separator: "\n\n---\n\n")
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .plainText, .rtf, .image, .init(filenameExtension: "docx")!, .init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            fileURL = url; pastedImage = nil; pastedImageName = ""; sourceText = ""; sections = []; progress = 0; errorMessage = nil
            status = ""
        }
    }

    func pasteImage() {
        guard let image = NSImage(pasteboard: .general) else {
            errorMessage = "剪贴板中没有可用的图片。"
            return
        }
        pastedImage = image; pastedImageName = "剪贴板图片"; fileURL = nil
        sourceText = ""; sections = []; progress = 0; errorMessage = nil
        status = ""
    }

    var displayName: String { fileURL?.lastPathComponent ?? pastedImageName }
    var previewImage: NSImage? {
        if let pastedImage { return pastedImage }
        guard let fileURL, ["png", "jpg", "jpeg", "heic", "tif", "tiff", "bmp"].contains(fileURL.pathExtension.lowercased()) else { return nil }
        return NSImage(contentsOf: fileURL)
    }

    func extractText() {
        guard fileURL != nil || pastedImage != nil else { return }
        task?.cancel()
        isWorking = true; activity = "extract"; sourceText = ""; sections = []; progress = 0; errorMessage = nil
        task = Task {
            do {
                let service = DocumentImportService()
                let extracted: String
                if let pastedImage {
                    status = "正在识别剪贴板图片…"; progress = 0.08
                    extracted = try await service.extractText(from: pastedImage)
                    progress = 0.3
                } else if let fileURL {
                    extracted = try await service.extractText(from: fileURL) { value, message in
                        await MainActor.run { self.progress = value; self.status = message }
                    }
                } else { throw DocumentImportError.unreadable }
                sourceText = extracted
                progress = 1; status = "文字提取完成，请检查内容后决定是否翻译"; isWorking = false; activity = ""
            } catch is CancellationError {
                status = "已停止提取"; isWorking = false; activity = ""
            } catch {
                errorMessage = error.localizedDescription; status = "文字提取失败"; isWorking = false; activity = ""
            }
        }
    }

    func translate(using appState: AppState) {
        let cleaned = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        task?.cancel()
        isWorking = true; activity = "translate"; sections = []; progress = 0; errorMessage = nil
        task = Task {
            do {
                let chunks = DocumentImportService.chunks(from: cleaned)
                guard !chunks.isEmpty else { throw DocumentImportError.noText }
                for (index, chunk) in chunks.enumerated() {
                    try Task.checkCancellation()
                    status = "正在翻译第 \(index + 1)/\(chunks.count) 段…"
                    progress = Double(index) / Double(chunks.count)
                    let translated = try await appState.translateDocumentChunk(chunk, source: sourceLanguage, target: targetLanguage)
                    sections.append(.init(source: chunk, translation: translated))
                }
                progress = 1; status = "翻译完成"; isWorking = false; activity = ""
            } catch is CancellationError {
                status = "已暂停"; isWorking = false; activity = ""
            } catch {
                errorMessage = error.localizedDescription; status = "翻译失败"; isWorking = false; activity = ""
            }
        }
    }

    func cancel() { task?.cancel() }

    func clearTranslationOutputIfSourceIsEmpty() {
        guard sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if activity == "translate" { task?.cancel() }
        sections = []; progress = 0; status = ""; errorMessage = nil
    }

    func export() {
        guard !resultText.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportFormat == .markdown ? .init(filenameExtension: "md")! : .plainText]
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? (pastedImageName.isEmpty ? "PallasOwl-文档" : pastedImageName)
        panel.nameFieldStringValue = "\(base)-译文.\(exportFormat.fileExtension)"
        if panel.runModal() == .OK, let url = panel.url { try? exportText(title: base).write(to: url, atomically: true, encoding: .utf8) }
    }

    private func exportText(title: String) -> String {
        guard exportFormat == .markdown else { return resultText }
        let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let date = ISO8601DateFormatter().string(from: Date())
        let frontmatter = """
        ---
        title: "\(safeTitle) 译文"
        source: "\(safeTitle)"
        translated_at: "\(date)"
        source_language: "\(sourceLanguage.name)"
        target_language: "\(targetLanguage.name)"
        output_style: "\(outputStyle.rawValue)"
        tags:
          - PallasOwl
          - 翻译
        ---

        # \(title) 译文

        """
        if outputStyle == .translated {
            return frontmatter + sections.map(\.translation).joined(separator: "\n\n") + "\n"
        }
        let rows = sections.map { "| \(tableCell($0.source)) | \(tableCell($0.translation)) |" }.joined(separator: "\n")
        return frontmatter + "| 原文 | 译文 |\n|---|---|\n" + rows + "\n"
    }

    private func tableCell(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}

struct DocumentTranslationView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings
    @State private var model = DocumentTranslationModel()
    var embedded = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 14) {
            HStack {
                Button { model.chooseFile() } label: { Label("选择文档", systemImage: "doc.badge.plus") }
                    .buttonStyle(.borderedProminent)
                Button { model.pasteImage() } label: { Label("粘贴图片", systemImage: "photo.on.rectangle") }
                Spacer()
                Picker("输出", selection: $model.outputStyle) { ForEach(DocumentOutputStyle.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 150)
            }
            filePreview
            HStack {
                Picker("原文", selection: $model.sourceLanguage) { ForEach(Language.supported) { Text($0.name).tag($0) } }.labelsHidden()
                Image(systemName: "arrow.right")
                Picker("译文", selection: $model.targetLanguage) { ForEach(Language.supported.filter { $0.code != "auto" }) { Text($0.name).tag($0) } }.labelsHidden()
                Spacer()
            }
            HSplitView {
                sourcePane
                textPane("翻译结果", text: model.resultText, placeholder: "翻译结果会逐段显示在这里")
            }
            if model.isWorking || model.progress > 0 {
                VStack(spacing: 5) {
                    ProgressView(value: model.progress)
                    HStack { Text(model.status); Spacer(); Text("\(Int(model.progress * 100))%") }.font(.caption).foregroundStyle(.secondary)
                }
            } else if !model.status.isEmpty { Text(model.status).font(.caption).foregroundStyle(.secondary) }
            if let error = model.errorMessage { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Button { UserDefaults.standard.set("文档翻译", forKey: "requestedSettingsCategory"); openSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("打开文档翻译设置")
                Text("· 当前服务：\(state.documentCurrentServiceName)")
                    .font(.caption).foregroundStyle(.secondary)
                if model.isWorking { Button("暂停", action: model.cancel) }
                Spacer()
                Picker("导出格式", selection: $model.exportFormat) { ForEach(DocumentExportFormat.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 160)
                Button("导出结果", action: model.export).disabled(model.resultText.isEmpty || model.isWorking)
                Button("开始翻译") { model.translate(using: state) }.buttonStyle(.borderedProminent).disabled(model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)
            }
        }.padding(embedded ? 12 : 18).frame(minWidth: embedded ? 720 : 900, minHeight: embedded ? 440 : 620)
        .onChange(of: model.sourceText) { _, value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.clearTranslationOutputIfSourceIsEmpty() }
        }
    }

    private var filePreview: some View {
        HStack(spacing: 14) {
            Group {
                if let image = model.previewImage { Image(nsImage: image).resizable().scaledToFit() }
                else { Image(systemName: model.fileURL?.pathExtension.lowercased() == "pdf" ? "doc.richtext.fill" : "doc.text.fill").resizable().scaledToFit().padding(15).foregroundStyle(.blue) }
            }.frame(width: 76, height: 64).background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 7) {
                Text(model.displayName.isEmpty ? "尚未选择文件" : model.displayName).fontWeight(.semibold).lineLimit(1)
                if !model.displayName.isEmpty { Label(model.fileURL == nil ? "图片粘贴成功" : "文件载入成功", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                else { Text("选择文件或从剪贴板粘贴图片").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }.padding(10).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }

    private var sourcePane: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text("提取原文").font(.headline); Spacer(); if !model.sourceText.isEmpty { Text("可检查并修改").font(.caption).foregroundStyle(.secondary) } }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.sourceText).font(.system(size: state.editorFontSize)).lineSpacing(state.editorLineSpacing).scrollContentBackground(.hidden).padding(6).background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                if model.sourceText.isEmpty { Text("可直接输入或粘贴文字，也可选择文件后点击“提取文字”").foregroundStyle(.tertiary).padding(14).allowsHitTesting(false) }
            }
            HStack {
                if !model.sourceText.isEmpty { Text("已提取 \(model.sourceText.count) 个字符").font(.caption).foregroundStyle(.secondary) }
                else if model.displayName.isEmpty { Text("可直接输入文字").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("提取文字") { model.extractText() }.disabled((model.fileURL == nil && model.pastedImage == nil) || model.isWorking)
            }.padding(.horizontal, 10).padding(.vertical, 7).background(.background.secondary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        }.frame(minWidth: 350)
    }

    private func textPane(_ title: String, text: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView { Text(text.isEmpty ? placeholder : text).foregroundStyle(text.isEmpty ? .tertiary : .primary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(12) }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }.frame(minWidth: 350)
    }
}
