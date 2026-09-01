import AppKit
import AVFoundation
import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "通用设置", translation = "文本翻译", writing = "AI 文本处理", document = "文档翻译", liveCaption = "实时字幕", shortcuts = "快捷键", about = "关于"
    var id: Self { self }
}

private struct AddEngineGrid: View {
    let entries: [ServiceEntry]
    let existingIDs: Set<String>
    let add: (ServiceEntry) -> Void
    private let columns = Array(repeating: GridItem(.fixed(150), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加引擎").font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    Button { add(entry) } label: {
                        HStack { Image(systemName: existingIDs.contains(entry.id) ? "checkmark.circle.fill" : entry.icon); Text(entry.name).lineLimit(1); Spacer() }
                            .frame(maxWidth: .infinity).padding(.horizontal, 9).padding(.vertical, 7)
                    }.buttonStyle(.plain).background(.background.secondary, in: RoundedRectangle(cornerRadius: 7)).disabled(existingIDs.contains(entry.id))
                }
            }
        }.padding(14).frame(width: 490)
    }
}

private struct ModelComboBox: NSViewRepresentable {
    @Binding var text: String
    let items: [String]

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.usesDataSource = false
        box.completes = true
        box.delegate = context.coordinator
        box.addItems(withObjectValues: items)
        box.stringValue = text
        return box
    }
    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.parent = self
        let values = box.objectValues.compactMap { $0 as? String }
        if values != items { box.removeAllItems(); box.addItems(withObjectValues: items) }
        if box.stringValue != text { box.stringValue = text }
    }
    final class Coordinator: NSObject, NSComboBoxDelegate, NSTextFieldDelegate {
        var parent: ModelComboBox
        init(_ parent: ModelComboBox) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) { if let box = notification.object as? NSComboBox { parent.text = box.stringValue } }
        func comboBoxSelectionDidChange(_ notification: Notification) { if let box = notification.object as? NSComboBox { parent.text = box.stringValue } }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var category: SettingsCategory = .general
    @State private var selectedTranslationID = ""
    @State private var selectedWritingID = ""
    @State private var selectedDocumentID = ""
    @State private var selectedLiveCaptionID = ""
    @State private var showsTranslationEngines = false
    @State private var showsWritingEngines = false
    @State private var showsDocumentEngines = false
    @State private var showsLiveCaptionEngines = false
    @State private var showsVoicePicker = false
    @AppStorage("instantSelectionEnabled") private var instantSelectionEnabled = false
    @AppStorage("instantSelectionAutomatic") private var instantSelectionAutomatic = false

    var body: some View {
        VStack(spacing: 18) {
            Picker("设置分类", selection: $category) { ForEach(SettingsCategory.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }
                .pickerStyle(.segmented).frame(width: 760)
            Group {
                switch category {
                case .general: generalSettings
                case .translation: translationSettings
                case .writing: writingSettings
                case .document: documentSettings
                case .liveCaption: liveCaptionSettings
                case .shortcuts: shortcutSettings
                case .about: aboutSettings
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(22).frame(minWidth: 860, minHeight: 610)
        .sheet(isPresented: $showsVoicePicker) { VoicePickerSheet(isPresented: $showsVoicePicker) }
        .onAppear {
            if let requested = UserDefaults.standard.string(forKey: "requestedSettingsCategory"), let target = SettingsCategory(rawValue: requested) {
                category = target
                UserDefaults.standard.removeObject(forKey: "requestedSettingsCategory")
            }
            selectedTranslationID = state.addedTranslationServices.first?.id ?? ""
            selectedWritingID = state.addedWritingServices.first?.id ?? ""
            selectedDocumentID = state.addedDocumentServices.first?.id ?? ""
            selectedLiveCaptionID = state.addedLiveCaptionServices.first?.id ?? ""
        }
        .onDisappear {
            // The Settings scene is reused by macOS. Reset the page so opening
            // Settings from the main window does not remain on the last page.
            category = .general
        }
    }

    private var liveCaptionSettings: some View {
        @Bindable var live = state.liveCaption
        return GroupBox {
            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
                header("实时字幕", "实时转写麦克风或应用声音，并按需要翻译为目标语言")
                Divider()
                liveCaptionEngineConfiguration
                    .padding(.vertical, 12)
                Divider()
                settingRow("声音来源", "麦克风需要麦克风权限；应用声音需要屏幕与系统音频录制权限") {
                    Picker("", selection: $live.audioSource) { ForEach(LiveAudioSource.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 160)
                }
                if live.audioSource == .application {
                    settingRow("指定应用", "仅捕获所选应用的播放声音；应用启动和退出后列表会自动更新") {
                        Picker("", selection: Binding(get: { live.selectedApplicationBundleID }, set: { id in
                            live.selectedApplicationBundleID = id
                            live.selectedApplicationName = runningApplications.first(where: { $0.bundleIdentifier == id })?.localizedName ?? ""
                        })) {
                            ForEach(runningApplications, id: \.bundleIdentifier) { app in
                                Text(app.localizedName ?? app.bundleIdentifier ?? "应用").tag(app.bundleIdentifier ?? "")
                            }
                        }.labelsHidden().frame(width: 210)
                    }
                }
                settingRow("输入语言", "自动检测使用系统识别语言启动，并根据识别文字判断实际语言") {
                    Picker("", selection: $live.sourceLanguage) { ForEach(Language.supported) { Text(LocalizedStringKey($0.name)).tag($0) } }.labelsHidden().frame(width: 160)
                }
                settingRow("目标语言", "检测到输入已经是目标语言时可以只转写、不翻译") {
                    Picker("", selection: $live.targetLanguage) { ForEach(Language.supported.filter { $0.code != "auto" }) { Text(LocalizedStringKey($0.name)).tag($0) } }.labelsHidden().frame(width: 160)
                }
                settingRow("目标语言语音仅转写", "输入语音与目标语言相同时只记录原文，避免重复翻译和消耗 Token") {
                    Toggle("", isOn: $live.skipTranslationForTargetLanguage).labelsHidden().toggleStyle(.switch)
                }
                settingRow("字幕内容", "选择悬浮字幕显示原文、译文或双语") {
                    Picker("", selection: $live.displayMode) { ForEach(LiveCaptionDisplayMode.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 160)
                }
                settingRow("悬浮字幕", "显示在所有桌面空间和全屏应用上方") {
                    Toggle("", isOn: $live.showsFloatingWindow).labelsHidden().toggleStyle(.switch)
                }
                settingRow("字幕字号", "调整悬浮字幕的文字大小") {
                    HStack { Slider(value: $live.captionFontSize, in: 16...42, step: 1).frame(width: 180); Text("\(Int(live.captionFontSize))") }
                }
                settingRow("权限检查", "首次使用后，可在系统设置中检查相关权限") {
                    HStack {
                        Button("麦克风") { openPrivacySettings("Privacy_Microphone") }
                        Button("语音识别") { openPrivacySettings("Privacy_SpeechRecognition") }
                        Button("屏幕与音频") { openPrivacySettings("Privacy_ScreenCapture") }
                    }
                }
                HStack { Spacer(); Button("保存") { live.saveSettings() }.buttonStyle(.borderedProminent) }
                    .padding(.top, 14)
              }.padding(12)
            }
        }
    }

    private var liveCaptionEngineConfiguration: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("与文本翻译共用引擎").fontWeight(.semibold)
                    Text("开启后自动使用文本翻译的当前引擎；关闭后使用下方独立配置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { state.liveCaptionEngineMode == .shared }, set: { enabled in
                    if enabled { state.liveCaptionEngineMode = .shared }
                    else if let first = state.addedLiveCaptionServices.first { state.setLiveCaptionServiceEnabled(first, enabled: true) }
                    try? state.saveSettings()
                })).labelsHidden().toggleStyle(.switch)
            }.padding(12).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            if state.liveCaptionEngineMode != .shared {
                HStack(alignment: .top, spacing: 14) {
                    serviceList(entries: state.addedLiveCaptionServices, selectedID: $selectedLiveCaptionID,
                        isEnabled: state.isLiveCaptionServiceEnabled, setEnabled: state.setLiveCaptionServiceEnabled,
                        remove: state.removeLiveCaptionService, addMenu: AnyView(liveCaptionAddMenu), showCurrent: false)
                    GroupBox { liveCaptionEngineDetail.padding(10) }
                }.frame(height: 270)
            }
        }
    }

    private var liveCaptionAddMenu: some View {
        Button { showsLiveCaptionEngines.toggle() } label: { Image(systemName: "plus") }
            .buttonStyle(.plain)
            .popover(isPresented: $showsLiveCaptionEngines) {
                AddEngineGrid(entries: allTranslationEntries, existingIDs: Set(state.addedLiveCaptionServiceIDs)) { entry in
                    state.addLiveCaptionService(entry); selectedLiveCaptionID = entry.id; showsLiveCaptionEngines = false
                }
            }
    }

    @ViewBuilder private var liveCaptionEngineDetail: some View {
        if let entry = ServiceEntry.from(id: selectedLiveCaptionID) {
            switch entry {
            case .system:
                VStack(alignment: .leading, spacing: 10) {
                    header("Apple 系统翻译", "在本机完成实时字幕翻译，无需 API Key")
                    Label("适合追求低延迟和隐私的实时字幕。", systemImage: "checkmark.shield")
                    Spacer(); validationFooter
                }
            case .deepl:
                VStack(alignment: .leading, spacing: 8) {
                    header("DeepL 翻译", "实时字幕独立 DeepL 配置")
                    SecureField("DeepL Authentication Key", text: Binding(get: { state.liveCaptionDeepLKey }, set: { state.liveCaptionDeepLKey = $0 }))
                    Picker("API", selection: Binding(get: { state.deepLAPIType }, set: { state.deepLAPIType = $0 })) { ForEach(DeepLAPIType.allCases) { Text($0.rawValue).tag($0) } }
                    Spacer(); validationFooter
                }
            case .ai(let preset):
                VStack(alignment: .leading, spacing: 8) {
                    header(preset.rawValue, "实时字幕独立 AI 配置")
                    TextField("API 地址", text: Binding(get: { state.liveCaptionEndpoint }, set: { state.liveCaptionEndpoint = $0 }))
                    SecureField("API Key", text: Binding(get: { state.liveCaptionAPIKey }, set: { state.liveCaptionAPIKey = $0 }))
                    TextField("模型", text: Binding(get: { state.liveCaptionModel }, set: { state.liveCaptionModel = $0 }))
                    Spacer(); validationFooter
                }.onAppear { if state.liveCaptionAIPreset != preset { state.selectLiveCaptionAI(preset) } }
            }
        } else {
            ContentUnavailableView("请选择实时字幕引擎", systemImage: "captions.bubble")
        }
    }

    private var validationFooter: some View {
        HStack {
            Text(state.validationMessage).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            Button("保存") { try? state.saveSettings() }
            Button("验证") { Task { await state.validateLiveCaptionEngine() } }.buttonStyle(.borderedProminent)
        }
    }

    private func openPrivacySettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private var runningApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private var translationSettings: some View {
        HStack(alignment: .top, spacing: 18) {
            serviceList(entries: state.addedTranslationServices, selectedID: $selectedTranslationID,
                isEnabled: state.isTranslationServiceEnabled, setEnabled: state.setTranslationServiceEnabled,
                remove: state.removeTranslationService, addMenu: AnyView(translationAddMenu), showCurrent: true)
            GroupBox {
                if let entry = ServiceEntry.from(id: selectedTranslationID) {
                    switch entry {
                    case .system: systemTranslationDetail
                    case .ai(let preset): AIProfileEditor(preset: preset, writing: false) { state.activateTranslationService(entry) }
                    case .deepl: deepLDetail
                    }
                } else { emptyServices("尚未添加翻译引擎") }
            }
        }
    }

    private var writingSettings: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("与文本翻译共用引擎").fontWeight(.semibold)
                    Text("开启后，润色、跨语写作和总结使用文本翻译当前的 AI 引擎与配置。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { state.writingUsesTranslationEngine }, set: { state.writingUsesTranslationEngine = $0; try? state.saveSettings() }))
                    .labelsHidden().toggleStyle(.switch)
            }.padding(14).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

            if state.writingUsesTranslationEngine {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        header("共用文本翻译引擎", "文本翻译当前引擎改变后，AI 文本处理会自动同步")
                        Divider()
                        if state.translationProvider != .ai {
                            Label("当前文本翻译引擎不支持 AI 文本处理，请选择一个 AI 引擎。", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        } else {
                            Label("当前引擎：\(state.translationAIPreset.rawValue)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        Spacer()
                        HStack { Spacer(); Button("验证") { Task { await state.validateAI(writing: true) } }.buttonStyle(.borderedProminent) }
                    }.padding(12)
                }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    serviceList(entries: state.addedWritingServices, selectedID: $selectedWritingID,
                        isEnabled: { $0.aiPreset.map { state.enabledWritingAIs.contains($0.rawValue) } ?? false },
                        setEnabled: { entry, enabled in if let preset = entry.aiPreset { state.setWritingAIEnabled(preset, enabled: enabled) } },
                        remove: { entry in if let preset = entry.aiPreset { state.removeWritingService(preset) } },
                        addMenu: AnyView(writingAddMenu), showCurrent: false)
                    GroupBox {
                        if let preset = ServiceEntry.from(id: selectedWritingID)?.aiPreset {
                            AIProfileEditor(preset: preset, writing: true) { state.selectWritingAI(preset) }
                        } else { emptyServices("尚未添加 AI 引擎") }
                    }
                }
            }
        }
    }

    private func serviceList(entries: [ServiceEntry], selectedID: Binding<String>,
        isEnabled: @escaping (ServiceEntry) -> Bool,
        setEnabled: @escaping (ServiceEntry, Bool) -> Void,
        remove: @escaping (ServiceEntry) -> Void,
        addMenu: AnyView, showCurrent: Bool) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(entries) { entry in
                        HStack(spacing: 9) {
                            Image(systemName: entry.icon).frame(width: 20)
                            Text(entry.name).lineLimit(1)
                            Spacer()
                            Toggle("", isOn: Binding(get: { isEnabled(entry) }, set: { setEnabled(entry, $0) }))
                                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
                        .background(selectedID.wrappedValue == entry.id ? Color.accentColor.opacity(0.16) : .clear)
                        .onTapGesture { selectedID.wrappedValue = entry.id }
                    }
                }
            }
            Divider()
            HStack(spacing: 0) {
                addMenu.frame(width: 42, height: 28)
                Divider().frame(height: 18)
                Button {
                    guard let entry = ServiceEntry.from(id: selectedID.wrappedValue) else { return }
                    let nextID = entries.first(where: { $0.id != entry.id })?.id ?? ""
                    remove(entry); selectedID.wrappedValue = nextID
                } label: { Image(systemName: "minus") }
                .buttonStyle(.plain).frame(width: 42, height: 28).disabled(selectedID.wrappedValue.isEmpty)
                Spacer()
            }.padding(.horizontal, 3)
        }.frame(width: 255).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var translationAddMenu: some View {
        Button { showsTranslationEngines.toggle() } label: { Image(systemName: "plus") }
            .buttonStyle(.plain)
            .popover(isPresented: $showsTranslationEngines) {
                AddEngineGrid(entries: allTranslationEntries, existingIDs: Set(state.addedTranslationServiceIDs)) { entry in
                    state.addTranslationService(entry); selectedTranslationID = entry.id; showsTranslationEngines = false
                }
            }
    }

    private func addTranslationButton(_ entry: ServiceEntry) -> some View {
        Button(entry.name) { state.addTranslationService(entry); selectedTranslationID = entry.id }
            .disabled(state.addedTranslationServiceIDs.contains(entry.id))
    }

    private var writingAddMenu: some View {
        Button { showsWritingEngines.toggle() } label: { Image(systemName: "plus") }
            .buttonStyle(.plain)
            .popover(isPresented: $showsWritingEngines) {
                AddEngineGrid(entries: AIProviderPreset.allCases.map(ServiceEntry.ai), existingIDs: Set(state.addedWritingServiceIDs)) { entry in
                    guard let preset = entry.aiPreset else { return }
                    state.addWritingService(preset); selectedWritingID = entry.id; showsWritingEngines = false
                }
            }
    }

    private var chineseProviders: [AIProviderPreset] { [.deepSeek, .qwen, .kimi, .doubao, .zhipu, .ernie, .hunyuan, .minimax, .siliconFlow] }
    private var internationalProviders: [AIProviderPreset] { [.openAI, .anthropic, .gemini, .xAI, .perplexity, .groq, .openRouter, .mistral, .cohere] }
    private var localProviders: [AIProviderPreset] { [.ollama, .custom] }
    private var allTranslationEntries: [ServiceEntry] { [.system, .deepl] + (chineseProviders + internationalProviders + localProviders).map(ServiceEntry.ai) }

    private var systemTranslationDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Apple 系统翻译", "使用 macOS Translation Framework，在本机完成翻译")
            Divider()
            Label("无需 API Key；需要 macOS 26 或更高版本及已下载的翻译语言包。", systemImage: "checkmark.shield")
            Text("语言包可在“系统设置 → 通用 → 语言与地区 → 翻译语言”中管理。").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(12)
    }

    private var deepLDetail: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 0) {
            header("DeepL 翻译", "使用 DeepL 官方 API 进行高质量文本翻译"); Divider()
            field("Key", "在 DeepL API 账户中申请 Authentication Key") { SecureField("DeepL Authentication Key", text: $state.deepLAPIKey) }
            field("API", "必须与注册时选择的 DeepL API 套餐一致") { Picker("", selection: $state.deepLAPIType) { ForEach(DeepLAPIType.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden() }
            field("Formality", "仅在 DeepL 支持的目标语言中生效") { Picker("", selection: $state.deepLFormality) { ForEach(DeepLFormality.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden() }
            Spacer()
            HStack {
                Text(state.validationMessage).font(.caption).foregroundStyle(.secondary); Spacer()
                Button("保存") { try? state.saveSettings() }
                Button("验证") { Task { await state.validateDeepL() } }.buttonStyle(.borderedProminent)
            }.padding(.top, 12)
        }.padding(12)
    }

    private var shortcutSettings: some View {
        GroupBox {
            VStack(spacing: 0) {
                header("全局快捷键", "在任意 App 中调用 PallasOwl Translator"); Divider()
                ForEach(ShortcutAction.allCases) { shortcutEditor($0) }
                if duplicateShortcuts { Label("存在重复快捷键，请修改后再使用。", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).padding(.top, 10) }
                Spacer()
                HStack { Button("恢复默认") { state.resetShortcuts() }; Spacer(); Button("授予辅助功能权限") { GlobalCaptureService.shared.requestAccessibilityPermission() } }
            }.padding(12)
        }
    }

    private var documentSettings: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("与文本翻译共用引擎").fontWeight(.semibold); Text("开启后，文档翻译自动使用文本翻译的当前引擎。相同配置无需重复保存。").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Toggle("", isOn: Binding(get: { state.documentEngineMode == .shared }, set: { enabled in
                    if enabled { state.documentEngineMode = .shared }
                    else if let first = state.addedDocumentServices.first(where: state.isDocumentServiceEnabled) { state.activateDocumentService(first) }
                    try? state.saveSettings()
                })).labelsHidden().toggleStyle(.switch)
            }.padding(14).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("与 AI 文本处理共用引擎").fontWeight(.semibold); Text("开启后，文档翻译使用润色、跨语写作和总结当前使用的 AI 引擎与配置。").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Toggle("", isOn: Binding(get: { state.documentEngineMode == .sharedWriting }, set: { enabled in
                    if enabled { state.documentEngineMode = .sharedWriting }
                    else if let first = state.addedDocumentServices.first(where: state.isDocumentServiceEnabled) { state.activateDocumentService(first) }
                    try? state.saveSettings()
                })).labelsHidden().toggleStyle(.switch)
            }.padding(14).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            if state.documentEngineMode == .shared {
                GroupBox { VStack(alignment: .leading, spacing: 12) { header("共用文本翻译引擎", "文本翻译当前引擎改变后，文档翻译会自动同步"); Divider(); Label("当前引擎：\(state.translationProvider.rawValue)", systemImage: "checkmark.circle.fill").foregroundStyle(.green); Spacer() }.padding(12) }
            } else if state.documentEngineMode == .sharedWriting {
                GroupBox { VStack(alignment: .leading, spacing: 12) { header("共用 AI 文本处理引擎", "AI 文本处理当前引擎改变后，文档翻译会自动同步"); Divider(); if state.writingUsesTranslationEngine && state.translationProvider == .deepl { Label("AI 文本处理当前间接使用 DeepL，无法用于文档 AI 翻译。", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) } else { Label("当前引擎：\(state.writingUsesTranslationEngine ? state.translationAIPreset.rawValue : state.writingAIPreset.rawValue)", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }; Spacer() }.padding(12) }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    documentServiceList
                    GroupBox {
                        if let entry = ServiceEntry.from(id: selectedDocumentID) {
                            switch entry {
                            case .system: emptyServices("文档翻译暂不使用 Apple 系统引擎")
                            case .ai(let preset): DocumentAIProfileEditor(preset: preset)
                            case .deepl: documentDeepLDetail
                            }
                        } else { emptyServices("尚未添加文档翻译引擎") }
                    }
                }
            }
        }
    }

    private var documentServiceList: some View {
        VStack(spacing: 0) {
            ScrollView { LazyVStack(spacing: 2) { ForEach(state.addedDocumentServices) { entry in
                HStack(spacing: 9) { Image(systemName: entry.icon).frame(width: 20); Text(entry.name); Spacer(); Toggle("", isOn: Binding(get: { state.isDocumentServiceEnabled(entry) }, set: { state.setDocumentServiceEnabled(entry, enabled: $0) })).labelsHidden().toggleStyle(.switch).controlSize(.mini) }
                    .padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle()).background(selectedDocumentID == entry.id ? Color.accentColor.opacity(0.16) : .clear).onTapGesture { selectedDocumentID = entry.id }
            } } }
            Divider()
            HStack(spacing: 0) {
                Button { showsDocumentEngines.toggle() } label: { Image(systemName: "plus") }.buttonStyle(.plain).frame(width: 42)
                    .popover(isPresented: $showsDocumentEngines) {
                        AddEngineGrid(entries: [.deepl] + AIProviderPreset.allCases.map(ServiceEntry.ai), existingIDs: Set(state.addedDocumentServiceIDs)) { entry in
                            state.addDocumentService(entry); selectedDocumentID = entry.id; showsDocumentEngines = false
                        }
                    }
                Divider().frame(height: 18)
                Button { guard let entry = ServiceEntry.from(id: selectedDocumentID) else { return }; let next = state.addedDocumentServices.first(where: { $0.id != entry.id })?.id ?? ""; state.removeDocumentService(entry); selectedDocumentID = next } label: { Image(systemName: "minus") }.buttonStyle(.plain).frame(width: 42).disabled(selectedDocumentID.isEmpty)
                Spacer()
            }.frame(height: 28)
        }.frame(width: 255).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var documentDeepLDetail: some View {
        VStack(alignment: .leading, spacing: 12) { header("DeepL 翻译", "文档翻译使用文本翻译中保存的 DeepL 账户配置"); Divider(); Label(state.deepLAPIKey.isEmpty ? "尚未配置 DeepL Key" : "DeepL Key 已配置", systemImage: state.deepLAPIKey.isEmpty ? "exclamationmark.triangle" : "checkmark.circle.fill").foregroundStyle(state.deepLAPIKey.isEmpty ? .orange : .green); Text("如需修改 Key、API 套餐或 Formality，请在“文本翻译”中选择 DeepL。").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(12)
    }

    private var generalSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                header("通用设置", "控制启动方式、界面语言和阅读体验"); Divider()
                settingRow("开机自动启动", "登录 macOS 后自动启动 PallasOwl Translator") {
                    Toggle("", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })).labelsHidden().toggleStyle(.switch)
                }
                settingRow("界面语言", "默认跟随 macOS；切换后界面立即刷新") {
                    Picker("", selection: Binding(get: { state.appLanguage }, set: { state.setAppLanguage($0) })) { ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) } }
                        .labelsHidden().frame(width: 180)
                }
                settingRow("选中即译", "在其他 App 中用鼠标选中文字后显示翻译入口；不影响现有划词翻译") {
                    Toggle("", isOn: $instantSelectionEnabled).labelsHidden().toggleStyle(.switch)
                        .onChange(of: instantSelectionEnabled) { _, enabled in GlobalCaptureService.shared.configureInstantSelection(enabled: enabled) }
                }
                if instantSelectionEnabled {
                    settingRow("选中即译方式", "默认先显示 T 图标，可改为选中后直接翻译") {
                        Picker("", selection: $instantSelectionAutomatic) {
                            Text("显示 T 图标").tag(false)
                            Text("自动显示结果").tag(true)
                        }.labelsHidden().frame(width: 170)
                    }
                }
                settingRow("正文字号", "调整原文和结果区域的字体大小") { slider(Binding(get: { state.editorFontSize }, set: { state.editorFontSize = $0 }), 14...22) }
                settingRow("正文行距", "调整长段落的阅读间距") { slider(Binding(get: { state.editorLineSpacing }, set: { state.editorLineSpacing = $0 }), 2...10) }
                settingRow("朗读语音", "来自 macOS 系统语音；自动模式会按文本语言选择") {
                    HStack {
                        Button {
                            showsVoicePicker = true
                        } label: {
                            Text(state.selectedVoiceIdentifier.isEmpty ? "自动选择" : (state.availableVoices.first { $0.identifier == state.selectedVoiceIdentifier }?.name ?? "选择语音"))
                                .frame(width: 210, alignment: .leading)
                        }
                        Button(state.isSpeaking ? "停止试听" : "试听") { state.toggleSpeechPreview() }
                    }
                }
                Spacer()
            }.padding(12)
        }
    }

    private var aboutSettings: some View {
        GroupBox {
            VStack(spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 92, height: 92)
                VStack(spacing: 6) {
                    Text("PallasOwl Translator").font(.title.bold())
                    Text("AI 翻译、文本处理、文档翻译与实时字幕")
                        .foregroundStyle(.secondary)
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("功能使用次数").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(UsageMetric.allCases) { metric in
                            HStack {
                                Text(metric.title).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(UsageMetrics.count(metric)) 次").monospacedDigit()
                            }
                        }
                    }
                    Text("仅保存在本机，不记录或上传处理内容。")
                        .font(.caption).foregroundStyle(.tertiary)
                }.frame(maxWidth: 520)
                Divider()
                VStack(spacing: 12) {
                    Link(destination: URL(string: "mailto:pallasowl2026@gmail.com")!) {
                        Label("pallasowl2026@gmail.com", systemImage: "envelope")
                    }
                    Link(destination: URL(string: "https://github.com/eric-cleath/FlowTranslate")!) {
                        Label("GitHub 项目", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: "https://github.com/eric-cleath/FlowTranslate/releases/latest")!) {
                        Label("查看最新版本", systemImage: "arrow.down.circle")
                    }
                }
                Spacer()
                Text("MIT License  ·  Copyright © 2026 PallasOwl")
                    .font(.caption).foregroundStyle(.tertiary)
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var buildNumber: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }

    private func slider(_ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack { Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; try? state.saveSettings() }), in: range, step: 1).frame(width: 180); Text("\(Int(value.wrappedValue))") }
    }
    private func emptyServices(_ title: String) -> some View { ContentUnavailableView(title, systemImage: "plus.circle", description: Text("使用左下角的 + 添加引擎")) }
    private func header(_ title: String, _ subtitle: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.title3.bold()); Text(subtitle).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 10) }
    private func field<C: View>(_ title: String, _ help: String, @ViewBuilder content: () -> C) -> some View { VStack(alignment: .leading, spacing: 7) { Text(title).fontWeight(.medium); content(); Text(help).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider() } }
    private func settingRow<C: View>(_ title: String, _ help: String, @ViewBuilder content: () -> C) -> some View { HStack { VStack(alignment: .leading, spacing: 4) { Text(title).fontWeight(.medium); Text(help).font(.caption).foregroundStyle(.secondary) }; Spacer(); content() }.padding(.vertical, 14).overlay(alignment: .bottom) { Divider() } }
    private func shortcutEditor(_ action: ShortcutAction) -> some View {
        let config = state.shortcuts[action] ?? .defaultValue(for: action)
        return HStack {
            Text(action.rawValue); Spacer()
            Toggle("⌃", isOn: shortcutBinding(action, \.control)).toggleStyle(.button)
            Toggle("⌥", isOn: shortcutBinding(action, \.option)).toggleStyle(.button)
            Toggle("⇧", isOn: shortcutBinding(action, \.shift)).toggleStyle(.button)
            Toggle("⌘", isOn: shortcutBinding(action, \.command)).toggleStyle(.button)
            Picker("", selection: Binding(get: { config.letter }, set: { value in var next = state.shortcuts[action] ?? config; next.letter = value; state.updateShortcut(action, next) })) { ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init), id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 60)
            Text(config.display).font(.system(.body, design: .monospaced)).frame(width: 70)
        }.padding(.vertical, 10).overlay(alignment: .bottom) { Divider() }
    }
    private func shortcutBinding(_ action: ShortcutAction, _ keyPath: WritableKeyPath<ShortcutConfig, Bool>) -> Binding<Bool> { Binding(get: { (state.shortcuts[action] ?? .defaultValue(for: action))[keyPath: keyPath] }, set: { value in var next = state.shortcuts[action] ?? .defaultValue(for: action); next[keyPath: keyPath] = value; state.updateShortcut(action, next) }) }
    private var duplicateShortcuts: Bool { let values = ShortcutAction.allCases.compactMap { state.shortcuts[$0]?.display }; return Set(values).count != values.count }
}

private struct VoicePickerSheet: View {
    @Environment(AppState.self) private var state
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var language = "全部语言"

    private var languages: [String] {
        ["全部语言"] + Set(state.availableVoices.map(\.language)).sorted()
    }

    private var voices: [AVSpeechSynthesisVoice] {
        state.availableVoices.filter { voice in
            (language == "全部语言" || voice.language == language) &&
            (searchText.isEmpty || voice.name.localizedCaseInsensitiveContains(searchText) || voice.language.localizedCaseInsensitiveContains(searchText))
        }.sorted { left, right in
            left.quality == right.quality ? (left.language, left.name) < (right.language, right.name) : left.quality.rawValue > right.quality.rawValue
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("选择朗读语音").font(.title2.bold())
                Spacer()
                Button("完成") { isPresented = false }.keyboardShortcut(.defaultAction)
            }
            HStack {
                TextField("搜索名称或语言", text: $searchText).textFieldStyle(.roundedBorder)
                Picker("语言", selection: $language) { ForEach(languages, id: \.self, content: Text.init) }.frame(width: 190)
            }
            Button {
                state.setSpeechVoice("")
            } label: {
                HStack { Image(systemName: state.selectedVoiceIdentifier.isEmpty ? "checkmark.circle.fill" : "circle"); Text("自动选择（根据文本语言）"); Spacer() }
            }.buttonStyle(.plain).padding(9).background(Color.accentColor.opacity(state.selectedVoiceIdentifier.isEmpty ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 8))
            List(voices, id: \.identifier) { voice in
                HStack {
                    Button { state.setSpeechVoice(voice.identifier) } label: {
                        HStack {
                            Image(systemName: state.selectedVoiceIdentifier == voice.identifier ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(voice.name)
                                Text("\(voice.language) · \(qualityName(voice.quality))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                    Spacer()
                    Button(state.isSpeaking && state.selectedVoiceIdentifier == voice.identifier ? "停止" : "试听") {
                        if state.selectedVoiceIdentifier != voice.identifier { state.setSpeechVoice(voice.identifier) }
                        state.toggleSpeechPreview()
                    }
                }.padding(.vertical, 3)
            }
            Text("显示 \(voices.count) 个语音；更多语音可在 macOS 系统设置中下载。").font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 570, height: 560)
    }

    private func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "高级"
        case .enhanced: "增强"
        default: "标准"
        }
    }
}

private struct AIProfileEditor: View {
    @Environment(AppState.self) private var state
    let preset: AIProviderPreset
    let writing: Bool
    let makeCurrent: () -> Void
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var message = ""
    @State private var validating = false
    @State private var models: [String] = []
    @State private var loadingModels = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) { Text(preset.rawValue).font(.title3.bold()); Text(writing ? "用于润色、跨语写作和总结" : "OpenAI Chat Completions 兼容服务").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 10)
            Divider()
            profileField("API 地址", "填写完整的 Chat Completions 地址") { TextField("https://…/chat/completions", text: $endpoint) }
            profileField("API Key", preset == .ollama ? "本地 Ollama 通常不需要 API Key" : "密钥仅保存在本机 macOS 钥匙串") { SecureField("sk-…", text: $apiKey) }
            profileField("模型", "从官方接口刷新当前账户可用模型，也可直接输入") {
                HStack {
                    ModelComboBox(text: $model, items: models).frame(height: 24)
                    Button(loadingModels ? "读取中…" : "刷新模型") { refreshModels() }.disabled(loadingModels)
                }
            }
            Spacer()
            HStack {
                Text(message).font(.caption).foregroundStyle(.secondary); Spacer()
                Button("保存", action: save)
                Button("验证") { save(); validating = true; Task { message = await state.validateAIProfile(preset, endpoint: endpoint, apiKey: apiKey, model: model); validating = false } }.buttonStyle(.borderedProminent).disabled(validating)
            }.padding(.top, 12)
        }.padding(12)
        .task(id: preset.id) { let p = state.loadAIProfile(preset, writing: writing); endpoint = p.endpoint; apiKey = p.apiKey; model = p.model; models = state.cachedModels(preset); message = "" }
    }
    private func save() { do { try state.saveAIProfile(preset, writing: writing, endpoint: endpoint, apiKey: apiKey, model: model); message = "已保存" } catch { message = "保存失败：\(error.localizedDescription)" } }
    private func refreshModels() { loadingModels = true; Task { do { models = try await state.fetchOfficialModels(preset, endpoint: endpoint, apiKey: apiKey); if model.isEmpty { model = models.first ?? "" }; message = "已读取 \(models.count) 个模型" } catch { message = "读取失败：\(error.localizedDescription)" }; loadingModels = false } }
    private func profileField<C: View>(_ title: String, _ help: String, @ViewBuilder content: () -> C) -> some View { VStack(alignment: .leading, spacing: 7) { Text(title).fontWeight(.medium); content(); Text(help).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider() } }
}

private struct DocumentAIProfileEditor: View {
    @Environment(AppState.self) private var state
    let preset: AIProviderPreset
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var message = ""
    @State private var validating = false
    @State private var models: [String] = []
    @State private var loadingModels = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) { Text(preset.rawValue).font(.title3.bold()); Text("用于文档分段翻译").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 10)
            Divider()
            profileField("API 地址", "填写完整的 Chat Completions 地址") { TextField("https://…/chat/completions", text: $endpoint) }
            profileField("API Key", preset == .ollama ? "本地 Ollama 通常不需要 API Key" : "密钥仅保存在本机 macOS 钥匙串") { SecureField("sk-…", text: $apiKey) }
            profileField("模型", "从官方接口刷新当前账户可用模型，也可直接输入") { HStack { ModelComboBox(text: $model, items: models).frame(height: 24); Button(loadingModels ? "读取中…" : "刷新模型") { refreshModels() }.disabled(loadingModels) } }
            Spacer()
            HStack { Text(message).font(.caption).foregroundStyle(.secondary); Spacer(); Button("保存", action: save); Button("验证") { save(); validating = true; Task { message = await state.validateAIProfile(preset, endpoint: endpoint, apiKey: apiKey, model: model); validating = false } }.buttonStyle(.borderedProminent).disabled(validating) }.padding(.top, 12)
        }.padding(12).task(id: preset.id) { let profile = state.loadDocumentAIProfile(preset); endpoint = profile.endpoint; apiKey = profile.apiKey; model = profile.model; models = state.cachedModels(preset); message = "" }
    }
    private func save() { do { try state.saveDocumentAIProfile(preset, endpoint: endpoint, apiKey: apiKey, model: model); message = "已保存" } catch { message = "保存失败：\(error.localizedDescription)" } }
    private func refreshModels() { loadingModels = true; Task { do { models = try await state.fetchOfficialModels(preset, endpoint: endpoint, apiKey: apiKey); if model.isEmpty { model = models.first ?? "" }; message = "已读取 \(models.count) 个模型" } catch { message = "读取失败：\(error.localizedDescription)" }; loadingModels = false } }
    private func profileField<C: View>(_ title: String, _ help: String, @ViewBuilder content: () -> C) -> some View { VStack(alignment: .leading, spacing: 7) { Text(title).fontWeight(.medium); content(); Text(help).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider() } }
}
