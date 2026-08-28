import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "通用设置"
    case translation = "文本翻译"
    case writing = "AI 文本处理"
    case shortcuts = "快捷键"
    var id: Self { self }
}

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var category: SettingsCategory = .translation
    @State private var selectedTranslation: TranslationProvider = .ai

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 18) {
            Picker("设置分类", selection: $category) {
                ForEach(SettingsCategory.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 360)

            Group {
                switch category {
                case .general: generalSettings
                case .translation: translationSettings
                case .writing: writingSettings
                case .shortcuts: shortcutSettings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(22)
        .frame(width: 840, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { selectedTranslation = state.translationProvider }
        .onChange(of: selectedTranslation) { _, value in
            state.validationMessage = ""
            state.selectTranslationProvider(value)
        }
    }

    private var translationSettings: some View {
        HStack(alignment: .top, spacing: 18) {
            serviceSidebar
            GroupBox {
                if selectedTranslation == .ai { aiDetail(writing: false) }
                else { deepLDetail }
            }
        }
    }

    private var serviceSidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(AIProviderPreset.allCases) { preset in
                        aiServiceRow(preset)
                    }
                    serviceRow(.deepl, enabled: Binding(get: { state.deepLEnabled }, set: { state.setTranslationServiceEnabled(.deepl, enabled: $0) }))
                }
            }
            Text("选择启用的服务作为当前翻译引擎")
                .font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .padding(8).frame(width: 225)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func aiServiceRow(_ preset: AIProviderPreset) -> some View {
        Button {
            state.selectTranslationAI(preset, activate: state.isTranslationAIEnabled(preset))
            selectedTranslation = .ai
        } label: {
            HStack {
                Image(systemName: preset == .ollama ? "desktopcomputer" : "sparkles").frame(width: 22)
                Text(preset.rawValue).fontWeight(.medium).lineLimit(1)
                Spacer()
                if state.translationProvider == .ai, state.translationAIPreset == preset {
                    Text("当前").font(.caption2).foregroundStyle(.blue)
                }
                Toggle("", isOn: Binding(
                    get: { state.isTranslationAIEnabled(preset) },
                    set: { state.setTranslationAIEnabled(preset, enabled: $0) }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }.padding(10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selectedTranslation == .ai && state.translationAIPreset == preset ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func serviceRow(_ provider: TranslationProvider, enabled: Binding<Bool>) -> some View {
        Button {
            selectedTranslation = provider
        } label: {
            HStack {
                Image(systemName: provider.icon).frame(width: 22)
                Text(provider.rawValue).fontWeight(.medium)
                Spacer()
                if state.translationProvider == provider { Text("当前").font(.caption2).foregroundStyle(.blue) }
                Toggle("", isOn: enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }.padding(10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selectedTranslation == provider ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func aiDetail(writing: Bool) -> some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 0) {
            detailHeader(
                title: writing ? "AI 文本处理" : "\(state.translationAIPreset.rawValue) 翻译",
                subtitle: writing ? "用于润色、跨语写作和总结" : "支持多种 OpenAI 兼容的 AI 翻译服务"
            )
            Divider()
            if writing {
                field("服务商", help: "选择常用服务后会自动填写 API 地址和推荐模型，也可以选择自定义") {
                    Picker("", selection: Binding(
                        get: { state.writingAIPreset },
                        set: { state.applyAIPreset($0, writing: true) }
                    )) {
                        ForEach(AIProviderPreset.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
            }
            field("API 地址", help: "填写完整的 Chat Completions 地址") {
                TextField("https://api.openai.com/v1/chat/completions", text: writing ? $state.writingEndpoint : $state.translationEndpoint)
            }
            field("API Key", help: "密钥仅保存在本机 macOS 钥匙串") {
                SecureField("sk-…", text: writing ? $state.writingAPIKey : $state.translationAPIKey)
            }
            field("模型", help: "填写服务支持的模型名称") {
                TextField("gpt-4.1-mini", text: writing ? $state.writingModel : $state.translationModel)
            }
            Spacer()
            validationFooter { Task { await state.validateAI(writing: writing) } }
        }.padding(12)
    }

    private var deepLDetail: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 0) {
            detailHeader(title: "DeepL 翻译", subtitle: "使用 DeepL 官方 API 进行高质量文本翻译")
            Divider()
            field("Key", help: "在 DeepL API 账户中申请 Authentication Key") {
                SecureField("DeepL Authentication Key", text: $state.deepLAPIKey)
            }
            field("API", help: "必须与注册时选择的 DeepL API 套餐一致") {
                Picker("", selection: $state.deepLAPIType) { ForEach(DeepLAPIType.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden()
            }
            field("Formality", help: "仅在 DeepL 支持的目标语言中生效") {
                Picker("", selection: $state.deepLFormality) { ForEach(DeepLFormality.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden()
            }
            field("支持语言", help: "中文、英语、日语、韩语及主要欧洲语言") {
                Text("由 DeepL API 动态支持").foregroundStyle(.secondary)
            }
            Spacer()
            validationFooter { Task { await state.validateDeepL() } }
        }.padding(12)
    }

    private var writingSettings: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "wand.and.stars").frame(width: 22)
                    Text("AI 文本处理").fontWeight(.medium)
                    Spacer()
                    Toggle("", isOn: Binding(get: { state.writingEnabled }, set: { state.writingEnabled = $0 })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }.padding(10).background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
            }.padding(8).frame(width: 225).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            GroupBox { aiDetail(writing: true) }
        }
    }

    private var shortcutSettings: some View {
        GroupBox {
            VStack(spacing: 0) {
                detailHeader(title: "全局快捷键", subtitle: "在任意 App 中调用 FlowTranslate")
                Divider()
                ForEach(ShortcutAction.allCases) { shortcutEditor($0) }
                if hasDuplicateShortcuts {
                    Label("存在重复快捷键，请修改后再使用。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).padding(.top, 10)
                }
                Spacer()
                HStack {
                    Button("恢复默认") { state.resetShortcuts() }
                    Spacer()
                    Button("授予辅助功能权限") { GlobalCaptureService.shared.requestAccessibilityPermission() }
                }
            }.padding(12)
        }
    }

    private var generalSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                detailHeader(title: "通用设置", subtitle: "控制启动方式和翻译窗口的阅读体验")
                Divider()
                settingRow("开机自动启动", help: "登录 macOS 后自动启动 FlowTranslate") {
                    Toggle("", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
                settingRow("正文字号", help: "调整原文和结果区域的字体大小") {
                    HStack { Slider(value: Binding(get: { state.editorFontSize }, set: { state.editorFontSize = $0; try? state.saveSettings() }), in: 14...22, step: 1).frame(width: 180); Text("\(Int(state.editorFontSize))") }
                }
                settingRow("正文行距", help: "调整长段落的阅读间距") {
                    HStack { Slider(value: Binding(get: { state.editorLineSpacing }, set: { state.editorLineSpacing = $0; try? state.saveSettings() }), in: 2...10, step: 1).frame(width: 180); Text("\(Int(state.editorLineSpacing))") }
                }
                Spacer()
            }.padding(12)
        }
    }

    private func detailHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.title3.bold()); Text(subtitle).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 10)
    }
    private func field<Content: View>(_ title: String, help: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).fontWeight(.medium); content(); Text(help).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider() }
    }
    private func validationFooter(action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: state.validationMessage.hasPrefix("验证成功") ? "checkmark.circle.fill" : "info.circle")
                .foregroundStyle(state.validationMessage.hasPrefix("验证成功") ? .green : .secondary)
            Text(state.validationMessage).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("保存") { try? state.saveSettings() }
            Button("验证", action: action).buttonStyle(.borderedProminent).disabled(state.isValidating)
        }.padding(.top, 12)
    }
    private func shortcutRow(_ title: String, keys: String) -> some View {
        HStack { Text(title); Spacer(); Text(keys).font(.system(.body, design: .monospaced)).padding(.horizontal, 12).padding(.vertical, 6).background(.quaternary, in: RoundedRectangle(cornerRadius: 7)) }.padding(.vertical, 13).overlay(alignment: .bottom) { Divider() }
    }

    private func shortcutEditor(_ action: ShortcutAction) -> some View {
        let config = state.shortcuts[action] ?? .defaultValue(for: action)
        return HStack {
            Text(action.rawValue)
            Spacer()
            Toggle("⌃", isOn: shortcutBinding(action, \.control)).toggleStyle(.button)
            Toggle("⌥", isOn: shortcutBinding(action, \.option)).toggleStyle(.button)
            Toggle("⇧", isOn: shortcutBinding(action, \.shift)).toggleStyle(.button)
            Toggle("⌘", isOn: shortcutBinding(action, \.command)).toggleStyle(.button)
            Picker("", selection: Binding(get: { config.letter }, set: { value in var next = state.shortcuts[action] ?? config; next.letter = value; state.updateShortcut(action, next) })) {
                ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init), id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width: 60)
            Text(config.display).font(.system(.body, design: .monospaced)).frame(width: 70)
        }.padding(.vertical, 10).overlay(alignment: .bottom) { Divider() }
    }

    private func shortcutBinding(_ action: ShortcutAction, _ keyPath: WritableKeyPath<ShortcutConfig, Bool>) -> Binding<Bool> {
        Binding(get: { (state.shortcuts[action] ?? .defaultValue(for: action))[keyPath: keyPath] }, set: { value in
            var next = state.shortcuts[action] ?? .defaultValue(for: action)
            next[keyPath: keyPath] = value
            state.updateShortcut(action, next)
        })
    }

    private var hasDuplicateShortcuts: Bool {
        let values = ShortcutAction.allCases.compactMap { state.shortcuts[$0]?.display }
        return Set(values).count != values.count
    }

    private func settingRow<Content: View>(_ title: String, help: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text(title).fontWeight(.medium); Text(help).font(.caption).foregroundStyle(.secondary) }
            Spacer(); content()
        }.padding(.vertical, 14).overlay(alignment: .bottom) { Divider() }
    }
}
