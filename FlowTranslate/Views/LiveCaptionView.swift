import AppKit
import SwiftUI

struct LiveCaptionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = appState.liveCaption
        VStack(spacing: 14) {
            HStack {
                Picker("声音来源", selection: $model.audioSource) {
                    ForEach(LiveAudioSource.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }.frame(width: 170)
                if model.audioSource == .application {
                    applicationPicker(model: model)
                }
                languagePicker("输入语言", selection: $model.sourceLanguage, allowsAuto: true)
                Image(systemName: "arrow.right")
                languagePicker("目标语言", selection: $model.targetLanguage, allowsAuto: false)
                Picker("输出", selection: $model.outputStyle) {
                    ForEach(DocumentOutputStyle.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 145)
                Spacer()
                Button(model.isRunning ? "停止字幕" : "开始字幕") {
                    if model.isRunning { model.stop() }
                    else {
                        model.translateHandler = { text, source, target in
                            try await appState.translateLiveCaption(text, source: source, target: target)
                        }
                        Task { await model.start() }
                    }
                }.buttonStyle(.borderedProminent)
            }

            HSplitView {
                captionArea("实时原文", text: model.sourceText, placeholder: "识别出的语音会显示在这里")
                captionArea("实时译文", text: model.translatedText, placeholder: "翻译结果会显示在这里")
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button {
                    UserDefaults.standard.set("实时字幕", forKey: "requestedSettingsCategory")
                    openSettings()
                } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("实时字幕设置")
                Circle().fill(model.isRunning ? Color.green : Color.secondary).frame(width: 7, height: 7)
                Text(model.status).foregroundStyle(.secondary)
                if !model.detectedLanguageName.isEmpty { Text("· 检测语言：\(model.detectedLanguageName)").foregroundStyle(.secondary) }
                Spacer()
                Picker("导出格式", selection: $model.exportFormat) {
                    ForEach(DocumentExportFormat.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 160)
                Button("导出结果") { model.export() }
                    .disabled(model.outputStyle == .translated ? model.translatedText.isEmpty : (model.sourceText.isEmpty && model.translatedText.isEmpty))
                Button("清空记录") { model.clear() }.disabled(model.sourceText.isEmpty && model.translatedText.isEmpty)
            }.font(.caption)
        }
        .padding(.horizontal).padding(.bottom)
        .onAppear { model.setHostWindowVisible(true) }
        .onDisappear { model.setHostWindowVisible(false) }
    }

    private func applicationPicker(model: LiveCaptionModel) -> some View {
        let applications = runningApplications
        return Picker("应用", selection: Binding(get: { model.selectedApplicationBundleID }, set: { id in
            model.selectedApplicationBundleID = id
            model.selectedApplicationName = applications.first(where: { $0.bundleIdentifier == id })?.localizedName ?? ""
            model.saveSettings()
        })) {
            if applications.isEmpty { Text("没有可用应用").tag("") }
            ForEach(applications, id: \.bundleIdentifier) { app in
                Text(app.localizedName ?? app.bundleIdentifier ?? "应用").tag(app.bundleIdentifier ?? "")
            }
        }.frame(width: 170)
    }

    private var runningApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func languagePicker(_ title: String, selection: Binding<Language>, allowsAuto: Bool) -> some View {
        Picker(title, selection: selection) {
            ForEach(Language.supported.filter { allowsAuto || $0.code != "auto" }) { Text(LocalizedStringKey($0.name)).tag($0) }
        }.frame(width: 150)
    }

    private func captionArea(_ title: String, text: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                    .font(.system(size: appState.editorFontSize)).lineSpacing(appState.editorLineSpacing)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
            }.background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }.frame(minWidth: 300)
    }
}
