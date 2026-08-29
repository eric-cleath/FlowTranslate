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
    var sourceText = ""
    var sections: [DocumentTranslationSection] = []
    var progress = 0.0
    var status = "请选择要翻译的文档"
    var isWorking = false
    var errorMessage: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    var resultText: String {
        sections.map { section in
            outputStyle == .translated ? section.translation : "原文\n\(section.source)\n\n译文\n\(section.translation)"
        }.joined(separator: "\n\n---\n\n")
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .plainText, .rtf, .image, .init(filenameExtension: "docx")!, .init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            fileURL = url; pastedImage = nil; pastedImageName = ""; sourceText = ""; sections = []; progress = 0; errorMessage = nil
            status = "已选择 \(url.lastPathComponent)"
        }
    }

    func pasteImage() {
        guard let image = NSImage(pasteboard: .general) else {
            errorMessage = "剪贴板中没有可用的图片。"
            return
        }
        pastedImage = image; pastedImageName = "剪贴板图片"; fileURL = nil
        sourceText = ""; sections = []; progress = 0; errorMessage = nil
        status = "已粘贴图片，点击开始翻译"
    }

    func start(using appState: AppState) {
        guard fileURL != nil || pastedImage != nil else { return }
        task?.cancel()
        isWorking = true; sourceText = ""; sections = []; progress = 0; errorMessage = nil
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
                let chunks = DocumentImportService.chunks(from: extracted)
                guard !chunks.isEmpty else { throw DocumentImportError.noText }
                for (index, chunk) in chunks.enumerated() {
                    try Task.checkCancellation()
                    status = "正在翻译第 \(index + 1)/\(chunks.count) 段…"
                    progress = 0.3 + Double(index) / Double(chunks.count) * 0.68
                    let translated = try await appState.translateDocumentChunk(chunk, source: sourceLanguage, target: targetLanguage)
                    sections.append(.init(source: chunk, translation: translated))
                }
                progress = 1; status = "翻译完成"; isWorking = false
            } catch is CancellationError {
                status = "已暂停"; isWorking = false
            } catch {
                errorMessage = error.localizedDescription; status = "处理失败"; isWorking = false
            }
        }
    }

    func cancel() { task?.cancel() }

    func export() {
        guard !resultText.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "\(fileURL?.deletingPathExtension().lastPathComponent ?? pastedImageName)-译文.md"
        if panel.runModal() == .OK, let url = panel.url { try? resultText.write(to: url, atomically: true, encoding: .utf8) }
    }
}

struct DocumentTranslationView: View {
    @Environment(AppState.self) private var state
    @State private var model = DocumentTranslationModel()
    var embedded = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 14) {
            HStack {
                Button { model.chooseFile() } label: { Label("选择文档", systemImage: "doc.badge.plus") }
                    .buttonStyle(.borderedProminent)
                Button { model.pasteImage() } label: { Label("粘贴图片", systemImage: "photo.on.rectangle") }
                    .keyboardShortcut("v", modifiers: .command)
                Text(model.fileURL?.lastPathComponent ?? (model.pastedImageName.isEmpty ? "支持 PDF、Word、TXT、Markdown 和图片" : model.pastedImageName))
                    .lineLimit(1).foregroundStyle(.secondary)
                Spacer()
                Picker("输出", selection: $model.outputStyle) { ForEach(DocumentOutputStyle.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 150)
            }
            HStack {
                Picker("原文", selection: $model.sourceLanguage) { ForEach(Language.supported) { Text($0.name).tag($0) } }.labelsHidden()
                Image(systemName: "arrow.right")
                Picker("译文", selection: $model.targetLanguage) { ForEach(Language.supported.filter { $0.code != "auto" }) { Text($0.name).tag($0) } }.labelsHidden()
                Spacer()
                Text("引擎：\(state.documentEngineMode.rawValue)").font(.caption).foregroundStyle(.secondary)
            }
            HSplitView {
                textPane("提取原文", text: model.sourceText, placeholder: "读取后的文字会显示在这里")
                textPane("翻译结果", text: model.resultText, placeholder: "翻译结果会逐段显示在这里")
            }
            if model.isWorking || model.progress > 0 {
                VStack(spacing: 5) {
                    ProgressView(value: model.progress)
                    HStack { Text(model.status); Spacer(); Text("\(Int(model.progress * 100))%") }.font(.caption).foregroundStyle(.secondary)
                }
            } else { Text(model.status).font(.caption).foregroundStyle(.secondary) }
            if let error = model.errorMessage { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                if model.isWorking { Button("暂停", action: model.cancel) }
                Spacer()
                Button("导出结果", action: model.export).disabled(model.resultText.isEmpty || model.isWorking)
                Button("开始翻译") { model.start(using: state) }.buttonStyle(.borderedProminent).disabled((model.fileURL == nil && model.pastedImage == nil) || model.isWorking)
            }
        }.padding(embedded ? 12 : 18).frame(minWidth: embedded ? 720 : 900, minHeight: embedded ? 440 : 620)
    }

    private func textPane(_ title: String, text: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView { Text(text.isEmpty ? placeholder : text).foregroundStyle(text.isEmpty ? .tertiary : .primary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(12) }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }.frame(minWidth: 350)
    }
}
