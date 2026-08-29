import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "通用设置", translation = "文本翻译", writing = "AI 文本处理", document = "文档翻译", shortcuts = "快捷键"
    var id: Self { self }
}

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var category: SettingsCategory = .translation
    @State private var selectedTranslationID = ""
    @State private var selectedWritingID = ""
    @State private var selectedDocumentID = ""

    var body: some View {
        VStack(spacing: 18) {
            Picker("设置分类", selection: $category) { ForEach(SettingsCategory.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }
                .pickerStyle(.segmented).frame(width: 580)
            Group {
                switch category {
                case .general: generalSettings
                case .translation: translationSettings
                case .writing: writingSettings
                case .document: documentSettings
                case .shortcuts: shortcutSettings
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(22).frame(minWidth: 860, minHeight: 610)
        .onAppear {
            selectedTranslationID = state.addedTranslationServices.first?.id ?? ""
            selectedWritingID = state.addedWritingServices.first?.id ?? ""
            selectedDocumentID = state.addedDocumentServices.first?.id ?? ""
        }
    }

    private var translationSettings: some View {
        HStack(alignment: .top, spacing: 18) {
            serviceList(entries: state.addedTranslationServices, selectedID: $selectedTranslationID,
                isEnabled: state.isTranslationServiceEnabled, setEnabled: state.setTranslationServiceEnabled,
                remove: state.removeTranslationService, addMenu: AnyView(translationAddMenu), showCurrent: true)
            GroupBox {
                if let entry = ServiceEntry.from(id: selectedTranslationID) {
                    switch entry {
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
                        if state.translationProvider == .deepl {
                            Label("DeepL 不支持 AI 文本处理，请在文本翻译中选择一个 AI 引擎。", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
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
                            if (showCurrent && state.isCurrentTranslationService(entry)) ||
                                (!showCurrent && entry.aiPreset == state.writingAIPreset && isEnabled(entry)) {
                                Text("当前").font(.caption2).foregroundStyle(.blue)
                            }
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
        Menu {
            ForEach(AIProviderPreset.allCases) { preset in
                Button(preset.rawValue) { state.addTranslationService(.ai(preset)); selectedTranslationID = ServiceEntry.ai(preset).id }
                    .disabled(state.addedTranslationServiceIDs.contains(ServiceEntry.ai(preset).id))
            }
            Divider()
            Button("DeepL 翻译") { state.addTranslationService(.deepl); selectedTranslationID = ServiceEntry.deepl.id }
                .disabled(state.addedTranslationServiceIDs.contains(ServiceEntry.deepl.id))
        } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton)
    }

    private var writingAddMenu: some View {
        Menu {
            ForEach(AIProviderPreset.allCases) { preset in
                Button(preset.rawValue) { state.addWritingService(preset); selectedWritingID = ServiceEntry.ai(preset).id }
                    .disabled(state.addedWritingServiceIDs.contains(ServiceEntry.ai(preset).id))
            }
        } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton)
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
                Button("设为当前") { state.activateTranslationService(.deepl) }
                Button("保存") { try? state.saveSettings() }
                Button("验证") { Task { await state.validateDeepL() } }.buttonStyle(.borderedProminent)
            }.padding(.top, 12)
        }.padding(12)
    }

    private var shortcutSettings: some View {
        GroupBox {
            VStack(spacing: 0) {
                header("全局快捷键", "在任意 App 中调用 PallasOwl"); Divider()
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
            if state.documentEngineMode == .shared {
                GroupBox { VStack(alignment: .leading, spacing: 12) { header("共用文本翻译引擎", "文本翻译当前引擎改变后，文档翻译会自动同步"); Divider(); Label("当前引擎：\(state.translationProvider.rawValue)", systemImage: "checkmark.circle.fill").foregroundStyle(.green); Spacer() }.padding(12) }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    documentServiceList
                    GroupBox {
                        if let entry = ServiceEntry.from(id: selectedDocumentID) {
                            switch entry {
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
                HStack(spacing: 9) { Image(systemName: entry.icon).frame(width: 20); Text(entry.name); Spacer(); if state.isCurrentDocumentService(entry) { Text("当前").font(.caption2).foregroundStyle(.blue) }; Toggle("", isOn: Binding(get: { state.isDocumentServiceEnabled(entry) }, set: { state.setDocumentServiceEnabled(entry, enabled: $0) })).labelsHidden().toggleStyle(.switch).controlSize(.mini) }
                    .padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle()).background(selectedDocumentID == entry.id ? Color.accentColor.opacity(0.16) : .clear).onTapGesture { selectedDocumentID = entry.id }
            } } }
            Divider()
            HStack(spacing: 0) {
                Menu { ForEach(AIProviderPreset.allCases) { preset in Button(preset.rawValue) { let entry = ServiceEntry.ai(preset); state.addDocumentService(entry); selectedDocumentID = entry.id }.disabled(state.addedDocumentServiceIDs.contains(ServiceEntry.ai(preset).id)) }; Divider(); Button("DeepL 翻译") { state.addDocumentService(.deepl); selectedDocumentID = ServiceEntry.deepl.id }.disabled(state.addedDocumentServiceIDs.contains(ServiceEntry.deepl.id)) } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).frame(width: 42)
                Divider().frame(height: 18)
                Button { guard let entry = ServiceEntry.from(id: selectedDocumentID) else { return }; let next = state.addedDocumentServices.first(where: { $0.id != entry.id })?.id ?? ""; state.removeDocumentService(entry); selectedDocumentID = next } label: { Image(systemName: "minus") }.buttonStyle(.plain).frame(width: 42).disabled(selectedDocumentID.isEmpty)
                Spacer()
            }.frame(height: 28)
        }.frame(width: 255).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var documentDeepLDetail: some View {
        VStack(alignment: .leading, spacing: 12) { header("DeepL 翻译", "文档翻译使用文本翻译中保存的 DeepL 账户配置"); Divider(); Label(state.deepLAPIKey.isEmpty ? "尚未配置 DeepL Key" : "DeepL Key 已配置", systemImage: state.deepLAPIKey.isEmpty ? "exclamationmark.triangle" : "checkmark.circle.fill").foregroundStyle(state.deepLAPIKey.isEmpty ? .orange : .green); Text("如需修改 Key、API 套餐或 Formality，请在“文本翻译”中选择 DeepL。").font(.caption).foregroundStyle(.secondary); Spacer(); HStack { Spacer(); Button("设为当前") { state.activateDocumentService(.deepl) }.buttonStyle(.borderedProminent) } }.padding(12)
    }

    private var generalSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                header("通用设置", "控制启动方式、界面语言和阅读体验"); Divider()
                settingRow("开机自动启动", "登录 macOS 后自动启动 PallasOwl") {
                    Toggle("", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })).labelsHidden().toggleStyle(.switch)
                }
                settingRow("界面语言", "默认跟随 macOS；切换后界面立即刷新") {
                    Picker("", selection: Binding(get: { state.appLanguage }, set: { state.setAppLanguage($0) })) { ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) } }
                        .labelsHidden().frame(width: 180)
                }
                settingRow("正文字号", "调整原文和结果区域的字体大小") { slider(Binding(get: { state.editorFontSize }, set: { state.editorFontSize = $0 }), 14...22) }
                settingRow("正文行距", "调整长段落的阅读间距") { slider(Binding(get: { state.editorLineSpacing }, set: { state.editorLineSpacing = $0 }), 2...10) }
                Spacer()
            }.padding(12)
        }
    }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) { Text(preset.rawValue).font(.title3.bold()); Text(writing ? "用于润色、跨语写作和总结" : "OpenAI Chat Completions 兼容服务").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 10)
            Divider()
            profileField("API 地址", "填写完整的 Chat Completions 地址") { TextField("https://…/chat/completions", text: $endpoint) }
            profileField("API Key", preset == .ollama ? "本地 Ollama 通常不需要 API Key" : "密钥仅保存在本机 macOS 钥匙串") { SecureField("sk-…", text: $apiKey) }
            profileField("模型", "填写服务支持的模型名称") { TextField(preset.suggestedModel, text: $model) }
            Spacer()
            HStack {
                Text(message).font(.caption).foregroundStyle(.secondary); Spacer()
                Button("设为当前") { save(); makeCurrent() }
                Button("保存", action: save)
                Button("验证") { save(); validating = true; Task { message = await state.validateAIProfile(preset, endpoint: endpoint, apiKey: apiKey, model: model); validating = false } }.buttonStyle(.borderedProminent).disabled(validating)
            }.padding(.top, 12)
        }.padding(12)
        .task(id: preset.id) { let p = state.loadAIProfile(preset, writing: writing); endpoint = p.endpoint; apiKey = p.apiKey; model = p.model; message = "" }
    }
    private func save() { do { try state.saveAIProfile(preset, writing: writing, endpoint: endpoint, apiKey: apiKey, model: model); message = "已保存" } catch { message = "保存失败：\(error.localizedDescription)" } }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) { Text(preset.rawValue).font(.title3.bold()); Text("用于文档分段翻译").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 10)
            Divider()
            profileField("API 地址", "填写完整的 Chat Completions 地址") { TextField("https://…/chat/completions", text: $endpoint) }
            profileField("API Key", preset == .ollama ? "本地 Ollama 通常不需要 API Key" : "密钥仅保存在本机 macOS 钥匙串") { SecureField("sk-…", text: $apiKey) }
            profileField("模型", "填写服务支持的模型名称") { TextField(preset.suggestedModel, text: $model) }
            Spacer()
            HStack { Text(message).font(.caption).foregroundStyle(.secondary); Spacer(); Button("设为当前") { save(); state.activateDocumentService(.ai(preset)) }; Button("保存", action: save); Button("验证") { save(); validating = true; Task { message = await state.validateAIProfile(preset, endpoint: endpoint, apiKey: apiKey, model: model); validating = false } }.buttonStyle(.borderedProminent).disabled(validating) }.padding(.top, 12)
        }.padding(12).task(id: preset.id) { let profile = state.loadDocumentAIProfile(preset); endpoint = profile.endpoint; apiKey = profile.apiKey; model = profile.model; message = "" }
    }
    private func save() { do { try state.saveDocumentAIProfile(preset, endpoint: endpoint, apiKey: apiKey, model: model); message = "已保存" } catch { message = "保存失败：\(error.localizedDescription)" } }
    private func profileField<C: View>(_ title: String, _ help: String, @ViewBuilder content: () -> C) -> some View { VStack(alignment: .leading, spacing: 7) { Text(title).fontWeight(.medium); content(); Text(help).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider() } }
}
