import AppKit
import AVFoundation
import Foundation
import ServiceManagement

@MainActor
@Observable
final class AppState {
    var mode: WorkMode = .translate
    var sourceLanguage = Language.supported[0]
    var targetLanguage = Language.supported[1]
    var crossWritingTargetLanguage = Language.supported.first(where: { $0.code == (UserDefaults.standard.string(forKey: "crossWritingTargetLanguage") ?? "en") }) ?? Language.supported[3]
    var input = ""
    var output = ""
    var isWorking = false
    var processingStatus = ""
    var errorMessage: String?
    var keychainIssue: String?
    var history: [HistoryItem] = []

    var translationEndpoint = UserDefaults.standard.string(forKey: "translationEndpoint") ?? "https://api.openai.com/v1/chat/completions"
    var translationModel = UserDefaults.standard.string(forKey: "translationModel") ?? "gpt-4.1-mini"
    var translationAPIKey = KeychainStore.read(account: "translationAPIKey")
    var writingEndpoint = UserDefaults.standard.string(forKey: "writingEndpoint") ?? "https://api.openai.com/v1/chat/completions"
    var writingModel = UserDefaults.standard.string(forKey: "writingModel") ?? "gpt-4.1-mini"
    var writingAPIKey = KeychainStore.read(account: "writingAPIKey")
    var translationAIPreset = AIProviderPreset(rawValue: UserDefaults.standard.string(forKey: "translationAIPreset") ?? "") ?? .openAI
    var writingAIPreset = AIProviderPreset(rawValue: UserDefaults.standard.string(forKey: "writingAIPreset") ?? "") ?? .openAI
    var translationProvider = TranslationProvider(rawValue: UserDefaults.standard.string(forKey: "translationProvider") ?? "") ?? .ai
    var aiTranslationEnabled = UserDefaults.standard.object(forKey: "aiTranslationEnabled") as? Bool ?? true
    var enabledTranslationAIs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "enabledTranslationAIs") ?? [AIProviderPreset.openAI.rawValue])
    var deepLEnabled = UserDefaults.standard.object(forKey: "deepLEnabled") as? Bool ?? false
    var writingEnabled = UserDefaults.standard.object(forKey: "writingEnabled") as? Bool ?? true
    var deepLAPIKey = KeychainStore.read(account: "deepLAPIKey")
    var deepLAPIType = DeepLAPIType(rawValue: UserDefaults.standard.string(forKey: "deepLAPIType") ?? "") ?? .free
    var deepLFormality = DeepLFormality(rawValue: UserDefaults.standard.string(forKey: "deepLFormality") ?? "") ?? .default
    var validationMessage = ""
    var isValidating = false
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var editorFontSize = UserDefaults.standard.object(forKey: "editorFontSize") as? Double ?? 16
    var editorLineSpacing = UserDefaults.standard.object(forKey: "editorLineSpacing") as? Double ?? 5
    var shortcuts: [ShortcutAction: ShortcutConfig] = AppState.loadShortcuts()

    private let service = AIService()
    private let deepLService = DeepLService()
    @ObservationIgnored private let speechSynthesizer = AVSpeechSynthesizer()
    private let historyURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "FlowTranslate/history.json")
    }()

    init() {
        loadHistory()
        normalizeTranslationProvider()
    }

    func run() async {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let isTranslation = mode == .translate
        let effectiveSource = mode == .crossLanguageWriting ? (Language.supported.first { $0.code == "zh-Hans" } ?? sourceLanguage) : sourceLanguage
        let effectiveTarget = mode == .crossLanguageWriting ? crossWritingTargetLanguage : targetLanguage
        reloadSecretsIfNeeded()
        let activeProvider = resolvedTranslationProvider()
        if isTranslation && activeProvider == nil {
            errorMessage = "请先在设置中启用 AI 翻译或 DeepL 翻译服务。"
            return
        }
        if isTranslation && activeProvider == .deepl {
            guard deepLEnabled, !deepLAPIKey.isEmpty else { errorMessage = "请先启用并配置 DeepL 翻译服务。"; return }
            isWorking = true; processingStatus = "正在请求 DeepL…"; output = ""; errorMessage = nil
            do {
                let result = try await deepLService.translate(text: cleaned, target: targetLanguage, apiKey: deepLAPIKey, apiType: deepLAPIType, formality: deepLFormality)
                output = result
                history.insert(.init(mode: mode, source: cleaned, result: result, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage), at: 0)
                saveHistory()
            } catch { errorMessage = error.localizedDescription }
            isWorking = false; processingStatus = ""
            return
        }
        if isTranslation && activeProvider == .ai && !aiTranslationEnabled { errorMessage = "AI 翻译服务尚未启用。"; return }
        if !isTranslation && !writingEnabled { errorMessage = "AI 文本处理服务尚未启用。"; return }
        let endpoint = isTranslation ? translationEndpoint : writingEndpoint
        let savedAPIKey = isTranslation ? translationAPIKey : writingAPIKey
        let preset = isTranslation ? translationAIPreset : writingAIPreset
        let apiKey = savedAPIKey.isEmpty && preset == .ollama ? "ollama" : savedAPIKey
        let model = isTranslation ? translationModel : writingModel
        guard let url = URL(string: endpoint), !apiKey.isEmpty, !model.isEmpty else {
            errorMessage = apiKey.isEmpty && keychainIssue != nil ? "暂时无法读取 macOS 钥匙串，请确认电脑已解锁后重试。" : ServiceError.invalidConfiguration.localizedDescription
            return
        }
        isWorking = true
        processingStatus = mode == .crossLanguageWriting ? "正在生成跨语写作内容…" : "正在处理…"
        output = ""
        errorMessage = nil
        do {
            let result = try await service.perform(
                text: cleaned,
                mode: mode,
                source: effectiveSource,
                target: effectiveTarget,
                configuration: .init(endpoint: url, apiKey: apiKey, model: model)
            )
            output = result
            history.insert(.init(mode: mode, source: cleaned, result: result, sourceLanguage: effectiveSource, targetLanguage: effectiveTarget), at: 0)
            if history.count > 200 { history.removeLast(history.count - 200) }
            saveHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
        processingStatus = ""
    }

    func swapLanguages() {
        guard sourceLanguage.code != "auto" else { return }
        (sourceLanguage, targetLanguage) = (targetLanguage, sourceLanguage)
        (input, output) = (output, input)
    }

    func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }

    func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func speak(_ text: String, language: Language) {
        guard !text.isEmpty else { return }
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        let code: String
        switch language.code { case "zh-Hans": code = "zh-CN"; case "zh-Hant": code = "zh-TW"; case "ja": code = "ja-JP"; case "ko": code = "ko-KR"; default: code = "en-US" }
        utterance.voice = AVSpeechSynthesisVoice(language: code)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.speak(utterance)
    }

    func saveSettings() throws {
        UserDefaults.standard.set(translationEndpoint, forKey: "translationEndpoint")
        UserDefaults.standard.set(translationModel, forKey: "translationModel")
        UserDefaults.standard.set(writingEndpoint, forKey: "writingEndpoint")
        UserDefaults.standard.set(writingModel, forKey: "writingModel")
        UserDefaults.standard.set(translationAIPreset.rawValue, forKey: "translationAIPreset")
        UserDefaults.standard.set(writingAIPreset.rawValue, forKey: "writingAIPreset")
        UserDefaults.standard.set(translationProvider.rawValue, forKey: "translationProvider")
        UserDefaults.standard.set(aiTranslationEnabled, forKey: "aiTranslationEnabled")
        UserDefaults.standard.set(deepLEnabled, forKey: "deepLEnabled")
        UserDefaults.standard.set(writingEnabled, forKey: "writingEnabled")
        UserDefaults.standard.set(Array(enabledTranslationAIs), forKey: "enabledTranslationAIs")
        UserDefaults.standard.set(editorFontSize, forKey: "editorFontSize")
        UserDefaults.standard.set(editorLineSpacing, forKey: "editorLineSpacing")
        UserDefaults.standard.set(crossWritingTargetLanguage.code, forKey: "crossWritingTargetLanguage")
        UserDefaults.standard.set(deepLAPIType.rawValue, forKey: "deepLAPIType")
        UserDefaults.standard.set(deepLFormality.rawValue, forKey: "deepLFormality")
        if !translationAPIKey.isEmpty { try KeychainStore.save(translationAPIKey, account: "translationAPIKey") }
        if !writingAPIKey.isEmpty { try KeychainStore.save(writingAPIKey, account: "writingAPIKey") }
        if !deepLAPIKey.isEmpty { try KeychainStore.save(deepLAPIKey, account: "deepLAPIKey") }
        try saveTranslationAIProfile(translationAIPreset)
    }

    func selectTranslationProvider(_ provider: TranslationProvider) {
        translationProvider = provider
        if provider == .ai { aiTranslationEnabled = true }
        if provider == .deepl { deepLEnabled = true }
        persistTranslationPreferences()
    }

    func setTranslationServiceEnabled(_ provider: TranslationProvider, enabled: Bool) {
        if provider == .ai { aiTranslationEnabled = enabled }
        else { deepLEnabled = enabled }
        normalizeTranslationProvider()
        persistTranslationPreferences()
    }

    func validateAI(writing: Bool) async {
        isValidating = true; validationMessage = "正在验证…"
        let endpoint = writing ? writingEndpoint : translationEndpoint
        let savedKey = writing ? writingAPIKey : translationAPIKey
        let preset = writing ? writingAIPreset : translationAIPreset
        let key = savedKey.isEmpty && preset == .ollama ? "ollama" : savedKey
        let model = writing ? writingModel : translationModel
        do {
            guard let url = URL(string: endpoint), !model.isEmpty else { throw ServiceError.invalidConfiguration }
            validationMessage = try await service.validate(configuration: .init(endpoint: url, apiKey: key, model: model))
        } catch { validationMessage = "验证失败：\(error.localizedDescription)" }
        isValidating = false
    }

    func validateDeepL() async {
        isValidating = true; validationMessage = "正在验证…"
        do { validationMessage = try await deepLService.validate(apiKey: deepLAPIKey, apiType: deepLAPIType) }
        catch { validationMessage = "验证失败：\(error.localizedDescription)" }
        isValidating = false
    }

    func applyAIPreset(_ preset: AIProviderPreset, writing: Bool) {
        if writing { writingAIPreset = preset }
        else { translationAIPreset = preset }
        guard preset != .custom else { return }
        if writing {
            writingEndpoint = preset.endpoint
            writingModel = preset.suggestedModel
        } else {
            translationEndpoint = preset.endpoint
            translationModel = preset.suggestedModel
        }
        try? saveSettings()
    }

    func selectTranslationAI(_ preset: AIProviderPreset, activate: Bool = true) {
        try? saveTranslationAIProfile(translationAIPreset)
        translationAIPreset = preset
        if activate {
            translationProvider = .ai
            aiTranslationEnabled = true
            enabledTranslationAIs.insert(preset.rawValue)
        }
        let suffix = profileSuffix(preset)
        translationEndpoint = UserDefaults.standard.string(forKey: "translationEndpoint.\(suffix)") ?? preset.endpoint
        translationModel = UserDefaults.standard.string(forKey: "translationModel.\(suffix)") ?? preset.suggestedModel
        translationAPIKey = KeychainStore.read(account: "translationAPIKey.\(suffix)")
        persistTranslationPreferences()
        UserDefaults.standard.set(preset.rawValue, forKey: "translationAIPreset")
        validationMessage = ""
    }

    func isTranslationAIEnabled(_ preset: AIProviderPreset) -> Bool { enabledTranslationAIs.contains(preset.rawValue) }

    func setTranslationAIEnabled(_ preset: AIProviderPreset, enabled: Bool) {
        if enabled {
            enabledTranslationAIs.insert(preset.rawValue)
            selectTranslationAI(preset)
        }
        else { enabledTranslationAIs.remove(preset.rawValue) }
        if !enabled, translationAIPreset == preset {
            if let next = AIProviderPreset.allCases.first(where: { enabledTranslationAIs.contains($0.rawValue) }) { selectTranslationAI(next) }
            else if deepLEnabled { translationProvider = .deepl }
        }
        aiTranslationEnabled = !enabledTranslationAIs.isEmpty
        persistTranslationPreferences()
        UserDefaults.standard.set(Array(enabledTranslationAIs), forKey: "enabledTranslationAIs")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            errorMessage = "无法更新开机启动设置：\(error.localizedDescription)"
        }
    }

    func updateShortcut(_ action: ShortcutAction, _ config: ShortcutConfig) {
        shortcuts[action] = config
        if let data = try? JSONEncoder().encode(shortcuts), let text = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(text, forKey: "shortcuts")
        }
        GlobalCaptureService.shared.reloadShortcuts(shortcuts)
    }

    func resetShortcuts() {
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, .defaultValue(for: $0)) })
        for (action, config) in shortcuts { updateShortcut(action, config) }
    }

    func reloadSecretsIfNeeded() {
        keychainIssue = nil
        if translationAPIKey.isEmpty {
            translationAPIKey = readSecret("translationAPIKey.\(profileSuffix(translationAIPreset))")
            if translationAPIKey.isEmpty { translationAPIKey = readSecret("translationAPIKey") }
        }
        if writingAPIKey.isEmpty { writingAPIKey = readSecret("writingAPIKey") }
        if deepLAPIKey.isEmpty { deepLAPIKey = readSecret("deepLAPIKey") }
    }

    func prepareInput(_ text: String, mode: WorkMode = .translate, activate: Bool = true) {
        self.mode = mode
        input = ""
        output = ""
        errorMessage = nil
        input = text
        if activate { NSApp.activate(ignoringOtherApps: true) }
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let value = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
        history = value
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: historyURL, options: .atomic)
    }

    private func resolvedTranslationProvider() -> TranslationProvider? {
        if translationProvider == .ai, !enabledTranslationAIs.contains(translationAIPreset.rawValue),
           let next = AIProviderPreset.allCases.first(where: { enabledTranslationAIs.contains($0.rawValue) }) {
            selectTranslationAI(next)
        }
        if translationProvider == .deepl && deepLEnabled { return .deepl }
        if translationProvider == .ai && aiTranslationEnabled { return .ai }
        if deepLEnabled { translationProvider = .deepl; persistTranslationPreferences(); return .deepl }
        if aiTranslationEnabled { translationProvider = .ai; persistTranslationPreferences(); return .ai }
        return nil
    }

    private func normalizeTranslationProvider() {
        if translationProvider == .deepl && deepLEnabled { return }
        if translationProvider == .ai && aiTranslationEnabled { return }
        if deepLEnabled { translationProvider = .deepl }
        else if aiTranslationEnabled { translationProvider = .ai }
    }

    private func persistTranslationPreferences() {
        UserDefaults.standard.set(translationProvider.rawValue, forKey: "translationProvider")
        UserDefaults.standard.set(aiTranslationEnabled, forKey: "aiTranslationEnabled")
        UserDefaults.standard.set(deepLEnabled, forKey: "deepLEnabled")
        UserDefaults.standard.set(Array(enabledTranslationAIs), forKey: "enabledTranslationAIs")
    }


    private func saveTranslationAIProfile(_ preset: AIProviderPreset) throws {
        let suffix = profileSuffix(preset)
        UserDefaults.standard.set(translationEndpoint, forKey: "translationEndpoint.\(suffix)")
        UserDefaults.standard.set(translationModel, forKey: "translationModel.\(suffix)")
        if !translationAPIKey.isEmpty { try KeychainStore.save(translationAPIKey, account: "translationAPIKey.\(suffix)") }
    }

    private func profileSuffix(_ preset: AIProviderPreset) -> String {
        switch preset {
        case .openAI: "openai"
        case .gemini: "gemini"
        case .deepSeek: "deepseek"
        case .groq: "groq"
        case .openRouter: "openrouter"
        case .ollama: "ollama"
        case .custom: "custom"
        }
    }

    private static func loadShortcuts() -> [ShortcutAction: ShortcutConfig] {
        if let text = UserDefaults.standard.string(forKey: "shortcuts"), let data = text.data(using: .utf8),
           let value = try? JSONDecoder().decode([ShortcutAction: ShortcutConfig].self, from: data) { return value }
        return Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, .defaultValue(for: $0)) })
    }

    private func readSecret(_ account: String) -> String {
        do { return try KeychainStore.readValue(account: account) }
        catch KeychainStore.KeychainError.status(let status) {
            if status != errSecItemNotFound { keychainIssue = "钥匙串错误：\(status)" }
            return ""
        } catch { keychainIssue = error.localizedDescription; return "" }
    }
}
