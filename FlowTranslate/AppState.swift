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
    var addedTranslationServiceIDs = UserDefaults.standard.stringArray(forKey: "addedTranslationServiceIDs") ?? []
    var addedWritingServiceIDs = UserDefaults.standard.stringArray(forKey: "addedWritingServiceIDs") ?? []
    var enabledWritingAIs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "enabledWritingAIs") ?? [])
    var writingUsesTranslationEngine = UserDefaults.standard.object(forKey: "writingUsesTranslationEngine") as? Bool ?? false
    var documentEngineMode = DocumentEngineMode(rawValue: UserDefaults.standard.string(forKey: "documentEngineMode") ?? "") ?? .shared
    var documentAIPreset = AIProviderPreset(rawValue: UserDefaults.standard.string(forKey: "documentAIPreset") ?? "") ?? .openAI
    var documentEndpoint = UserDefaults.standard.string(forKey: "documentEndpoint") ?? "https://api.openai.com/v1/chat/completions"
    var documentModel = UserDefaults.standard.string(forKey: "documentModel") ?? "gpt-4.1-mini"
    var documentAPIKey = KeychainStore.read(account: "documentAPIKey")
    var addedDocumentServiceIDs = UserDefaults.standard.stringArray(forKey: "addedDocumentServiceIDs") ?? []
    var enabledDocumentAIs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "enabledDocumentAIs") ?? [])
    var documentDeepLEnabled = UserDefaults.standard.object(forKey: "documentDeepLEnabled") as? Bool ?? false
    var appLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
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
        migrateServiceListsIfNeeded()
        migrateDocumentServiceListIfNeeded()
        loadHistory()
        normalizeTranslationProvider()
    }

    var locale: Locale { Locale(identifier: appLanguage.localeIdentifier ?? Locale.current.identifier) }

    var addedTranslationServices: [ServiceEntry] { addedTranslationServiceIDs.compactMap(ServiceEntry.from(id:)) }
    var addedWritingServices: [ServiceEntry] { addedWritingServiceIDs.compactMap(ServiceEntry.from(id:)) }
    var addedDocumentServices: [ServiceEntry] { addedDocumentServiceIDs.compactMap(ServiceEntry.from(id:)) }

    func run() async {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let isTranslation = mode == .translate
        let effectiveSource = mode == .crossLanguageWriting ? (Language.supported.first { $0.code == "zh-Hans" } ?? sourceLanguage) : sourceLanguage
        let effectiveTarget = mode == .crossLanguageWriting ? crossWritingTargetLanguage : targetLanguage
        await reloadSecretsWithRetry()
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
        if !isTranslation && !writingUsesTranslationEngine && !writingEnabled { errorMessage = "AI 文本处理服务尚未启用。"; return }
        if !isTranslation && writingUsesTranslationEngine && activeProvider == .deepl {
            errorMessage = "DeepL 不支持润色、跨语写作和总结，请为 AI 文本处理选择 AI 引擎。"
            return
        }
        let sharesTranslationAI = !isTranslation && writingUsesTranslationEngine
        let endpoint = (isTranslation || sharesTranslationAI) ? translationEndpoint : writingEndpoint
        let savedAPIKey = (isTranslation || sharesTranslationAI) ? translationAPIKey : writingAPIKey
        let preset = (isTranslation || sharesTranslationAI) ? translationAIPreset : writingAIPreset
        let apiKey = savedAPIKey.isEmpty && preset == .ollama ? "ollama" : savedAPIKey
        let model = (isTranslation || sharesTranslationAI) ? translationModel : writingModel
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
        UserDefaults.standard.set(addedTranslationServiceIDs, forKey: "addedTranslationServiceIDs")
        UserDefaults.standard.set(addedWritingServiceIDs, forKey: "addedWritingServiceIDs")
        UserDefaults.standard.set(Array(enabledWritingAIs), forKey: "enabledWritingAIs")
        UserDefaults.standard.set(writingUsesTranslationEngine, forKey: "writingUsesTranslationEngine")
        UserDefaults.standard.set(documentEngineMode.rawValue, forKey: "documentEngineMode")
        UserDefaults.standard.set(documentAIPreset.rawValue, forKey: "documentAIPreset")
        UserDefaults.standard.set(documentEndpoint, forKey: "documentEndpoint")
        UserDefaults.standard.set(documentModel, forKey: "documentModel")
        UserDefaults.standard.set(addedDocumentServiceIDs, forKey: "addedDocumentServiceIDs")
        UserDefaults.standard.set(Array(enabledDocumentAIs), forKey: "enabledDocumentAIs")
        UserDefaults.standard.set(documentDeepLEnabled, forKey: "documentDeepLEnabled")
        UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")
        UserDefaults.standard.set(Array(enabledTranslationAIs), forKey: "enabledTranslationAIs")
        UserDefaults.standard.set(editorFontSize, forKey: "editorFontSize")
        UserDefaults.standard.set(editorLineSpacing, forKey: "editorLineSpacing")
        UserDefaults.standard.set(crossWritingTargetLanguage.code, forKey: "crossWritingTargetLanguage")
        UserDefaults.standard.set(deepLAPIType.rawValue, forKey: "deepLAPIType")
        UserDefaults.standard.set(deepLFormality.rawValue, forKey: "deepLFormality")
        if !translationAPIKey.isEmpty { try KeychainStore.save(translationAPIKey, account: "translationAPIKey") }
        if !writingAPIKey.isEmpty { try KeychainStore.save(writingAPIKey, account: "writingAPIKey") }
        if !deepLAPIKey.isEmpty { try KeychainStore.save(deepLAPIKey, account: "deepLAPIKey") }
        if !documentAPIKey.isEmpty { try KeychainStore.save(documentAPIKey, account: "documentAPIKey") }
        try saveTranslationAIProfile(translationAIPreset)
        try saveWritingAIProfile(writingAIPreset)
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
        await reloadSecretsWithRetry()
        let shared = writing && writingUsesTranslationEngine
        if shared && resolvedTranslationProvider() == .deepl {
            validationMessage = "验证失败：DeepL 不支持 AI 文本处理。"
            isValidating = false
            return
        }
        let endpoint = (writing && !shared) ? writingEndpoint : translationEndpoint
        let savedKey = (writing && !shared) ? writingAPIKey : translationAPIKey
        let preset = (writing && !shared) ? writingAIPreset : translationAIPreset
        let key = savedKey.isEmpty && preset == .ollama ? "ollama" : savedKey
        let model = (writing && !shared) ? writingModel : translationModel
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

    func selectWritingAI(_ preset: AIProviderPreset) {
        try? saveWritingAIProfile(writingAIPreset)
        writingAIPreset = preset
        let suffix = profileSuffix(preset)
        writingEndpoint = UserDefaults.standard.string(forKey: "writingEndpoint.\(suffix)") ?? preset.endpoint
        writingModel = UserDefaults.standard.string(forKey: "writingModel.\(suffix)") ?? preset.suggestedModel
        writingAPIKey = KeychainStore.read(account: "writingAPIKey.\(suffix)")
        UserDefaults.standard.set(preset.rawValue, forKey: "writingAIPreset")
        validationMessage = ""
    }

    func addTranslationService(_ entry: ServiceEntry) {
        guard !addedTranslationServiceIDs.contains(entry.id) else { return }
        addedTranslationServiceIDs.append(entry.id)
        if case .ai(let preset) = entry { enabledTranslationAIs.insert(preset.rawValue) }
        else { deepLEnabled = true }
        activateTranslationService(entry)
        persistTranslationPreferences()
    }

    func removeTranslationService(_ entry: ServiceEntry) {
        addedTranslationServiceIDs.removeAll { $0 == entry.id }
        if case .ai(let preset) = entry { enabledTranslationAIs.remove(preset.rawValue) }
        else { deepLEnabled = false }
        aiTranslationEnabled = !enabledTranslationAIs.isEmpty
        normalizeTranslationProvider()
        if let next = addedTranslationServices.first(where: { isTranslationServiceEnabled($0) }) { activateTranslationService(next) }
        persistTranslationPreferences()
    }

    func activateTranslationService(_ entry: ServiceEntry) {
        switch entry {
        case .ai(let preset): selectTranslationAI(preset)
        case .deepl: selectTranslationProvider(.deepl)
        }
    }

    func isTranslationServiceEnabled(_ entry: ServiceEntry) -> Bool {
        switch entry { case .ai(let preset): enabledTranslationAIs.contains(preset.rawValue); case .deepl: deepLEnabled }
    }

    func setTranslationServiceEnabled(_ entry: ServiceEntry, enabled: Bool) {
        switch entry {
        case .ai(let preset): setTranslationAIEnabled(preset, enabled: enabled)
        case .deepl: setTranslationServiceEnabled(TranslationProvider.deepl, enabled: enabled)
        }
    }

    func isCurrentTranslationService(_ entry: ServiceEntry) -> Bool {
        switch entry {
        case .ai(let preset): translationProvider == .ai && translationAIPreset == preset && isTranslationAIEnabled(preset)
        case .deepl: translationProvider == .deepl && deepLEnabled
        }
    }

    func addWritingService(_ preset: AIProviderPreset) {
        let entry = ServiceEntry.ai(preset)
        guard !addedWritingServiceIDs.contains(entry.id) else { return }
        addedWritingServiceIDs.append(entry.id)
        enabledWritingAIs.insert(preset.rawValue)
        writingEnabled = true
        selectWritingAI(preset)
        try? saveSettings()
    }

    func removeWritingService(_ preset: AIProviderPreset) {
        addedWritingServiceIDs.removeAll { $0 == ServiceEntry.ai(preset).id }
        enabledWritingAIs.remove(preset.rawValue)
        if writingAIPreset == preset, let next = addedWritingServices.compactMap(\.aiPreset).first(where: { enabledWritingAIs.contains($0.rawValue) }) { selectWritingAI(next) }
        writingEnabled = !enabledWritingAIs.isEmpty
        try? saveSettings()
    }

    func setWritingAIEnabled(_ preset: AIProviderPreset, enabled: Bool) {
        if enabled { enabledWritingAIs.insert(preset.rawValue); selectWritingAI(preset) }
        else { enabledWritingAIs.remove(preset.rawValue) }
        writingEnabled = !enabledWritingAIs.isEmpty
        try? saveSettings()
    }

    func setAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
    }

    func loadAIProfile(_ preset: AIProviderPreset, writing: Bool) -> (endpoint: String, apiKey: String, model: String) {
        let suffix = profileSuffix(preset)
        let prefix = writing ? "writing" : "translation"
        let endpoint = UserDefaults.standard.string(forKey: "\(prefix)Endpoint.\(suffix)") ?? preset.endpoint
        let model = UserDefaults.standard.string(forKey: "\(prefix)Model.\(suffix)") ?? preset.suggestedModel
        let key = KeychainStore.read(account: "\(prefix)APIKey.\(suffix)")
        return (endpoint, key, model)
    }

    func saveAIProfile(_ preset: AIProviderPreset, writing: Bool, endpoint: String, apiKey: String, model: String) throws {
        let suffix = profileSuffix(preset)
        let prefix = writing ? "writing" : "translation"
        UserDefaults.standard.set(endpoint, forKey: "\(prefix)Endpoint.\(suffix)")
        UserDefaults.standard.set(model, forKey: "\(prefix)Model.\(suffix)")
        if !apiKey.isEmpty { try KeychainStore.save(apiKey, account: "\(prefix)APIKey.\(suffix)") }
        if writing && writingAIPreset == preset {
            writingEndpoint = endpoint; writingAPIKey = apiKey; writingModel = model
        } else if !writing && translationAIPreset == preset {
            translationEndpoint = endpoint; translationAPIKey = apiKey; translationModel = model
        }
    }

    func validateAIProfile(_ preset: AIProviderPreset, endpoint: String, apiKey: String, model: String) async -> String {
        let effectiveKey = apiKey.isEmpty && preset == .ollama ? "ollama" : apiKey
        do {
            guard let url = URL(string: endpoint), !model.isEmpty else { throw ServiceError.invalidConfiguration }
            return try await service.validate(configuration: .init(endpoint: url, apiKey: effectiveKey, model: model))
        } catch { return "验证失败：\(error.localizedDescription)" }
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
            if translationProvider != .ai || !enabledTranslationAIs.contains(translationAIPreset.rawValue) { selectTranslationAI(preset) }
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
        if documentAPIKey.isEmpty { documentAPIKey = readSecret("documentAPIKey") }
    }

    func reloadSecretsAfterUnlock() {
        guard keychainIssue != nil || translationAPIKey.isEmpty || writingAPIKey.isEmpty || deepLAPIKey.isEmpty else { return }
        Task { await reloadSecretsWithRetry() }
    }

    func translateDocumentChunk(_ text: String, source: Language, target: Language) async throws -> String {
        await reloadSecretsWithRetry()
        let provider: TranslationProvider
        switch documentEngineMode {
        case .shared:
            guard let current = resolvedTranslationProvider() else { throw ServiceError.invalidConfiguration }
            provider = current
        case .ai:
            guard enabledDocumentAIs.contains(documentAIPreset.rawValue) else { throw ServiceError.invalidConfiguration }
            provider = .ai
        case .deepl:
            guard documentDeepLEnabled else { throw ServiceError.invalidConfiguration }
            provider = .deepl
        }
        if provider == .deepl {
            guard !deepLAPIKey.isEmpty else { throw ServiceError.invalidConfiguration }
            return try await deepLService.translate(text: text, target: target, apiKey: deepLAPIKey, apiType: deepLAPIType, formality: deepLFormality)
        }
        let shared = documentEngineMode == .shared
        let preset = shared ? translationAIPreset : documentAIPreset
        let endpoint = shared ? translationEndpoint : documentEndpoint
        let model = shared ? translationModel : documentModel
        let storedKey = shared ? translationAPIKey : documentAPIKey
        let key = storedKey.isEmpty && preset == .ollama ? "ollama" : storedKey
        guard let url = URL(string: endpoint), !model.isEmpty, !key.isEmpty else { throw ServiceError.invalidConfiguration }
        return try await service.perform(text: text, mode: .translate, source: source, target: target,
                                         configuration: .init(endpoint: url, apiKey: key, model: model))
    }

    func applyDocumentAIPreset(_ preset: AIProviderPreset) {
        try? saveDocumentAIProfile(documentAIPreset)
        documentAIPreset = preset
        let suffix = profileSuffix(preset)
        documentEndpoint = UserDefaults.standard.string(forKey: "documentEndpoint.\(suffix)") ?? preset.endpoint
        documentModel = UserDefaults.standard.string(forKey: "documentModel.\(suffix)") ?? preset.suggestedModel
        documentAPIKey = KeychainStore.read(account: "documentAPIKey.\(suffix)")
        try? saveSettings()
    }

    func addDocumentService(_ entry: ServiceEntry) {
        guard !addedDocumentServiceIDs.contains(entry.id) else { return }
        addedDocumentServiceIDs.append(entry.id)
        setDocumentServiceEnabled(entry, enabled: true)
        activateDocumentService(entry)
    }

    func removeDocumentService(_ entry: ServiceEntry) {
        let wasCurrent = isCurrentDocumentService(entry)
        addedDocumentServiceIDs.removeAll { $0 == entry.id }
        if case .ai(let preset) = entry { enabledDocumentAIs.remove(preset.rawValue) } else { documentDeepLEnabled = false }
        if wasCurrent, let next = addedDocumentServices.first(where: isDocumentServiceEnabled) { activateDocumentService(next) }
        try? saveSettings()
    }

    func activateDocumentService(_ entry: ServiceEntry) {
        switch entry {
        case .ai(let preset): documentEngineMode = .ai; applyDocumentAIPreset(preset)
        case .deepl: documentEngineMode = .deepl
        }
        try? saveSettings()
    }

    func isDocumentServiceEnabled(_ entry: ServiceEntry) -> Bool {
        switch entry { case .ai(let preset): enabledDocumentAIs.contains(preset.rawValue); case .deepl: documentDeepLEnabled }
    }

    func setDocumentServiceEnabled(_ entry: ServiceEntry, enabled: Bool) {
        switch entry {
        case .ai(let preset): if enabled { enabledDocumentAIs.insert(preset.rawValue) } else { enabledDocumentAIs.remove(preset.rawValue) }
        case .deepl: documentDeepLEnabled = enabled
        }
        if enabled { activateDocumentService(entry) }
        else if isCurrentDocumentService(entry), let next = addedDocumentServices.first(where: isDocumentServiceEnabled) { activateDocumentService(next) }
        try? saveSettings()
    }

    func isCurrentDocumentService(_ entry: ServiceEntry) -> Bool {
        switch entry {
        case .ai(let preset): documentEngineMode == .ai && documentAIPreset == preset && enabledDocumentAIs.contains(preset.rawValue)
        case .deepl: documentEngineMode == .deepl && documentDeepLEnabled
        }
    }

    func loadDocumentAIProfile(_ preset: AIProviderPreset) -> (endpoint: String, apiKey: String, model: String) {
        let suffix = profileSuffix(preset)
        return (UserDefaults.standard.string(forKey: "documentEndpoint.\(suffix)") ?? preset.endpoint,
                KeychainStore.read(account: "documentAPIKey.\(suffix)"),
                UserDefaults.standard.string(forKey: "documentModel.\(suffix)") ?? preset.suggestedModel)
    }

    func saveDocumentAIProfile(_ preset: AIProviderPreset, endpoint: String? = nil, apiKey: String? = nil, model: String? = nil) throws {
        let suffix = profileSuffix(preset)
        let finalEndpoint = endpoint ?? documentEndpoint, finalKey = apiKey ?? documentAPIKey, finalModel = model ?? documentModel
        UserDefaults.standard.set(finalEndpoint, forKey: "documentEndpoint.\(suffix)")
        UserDefaults.standard.set(finalModel, forKey: "documentModel.\(suffix)")
        if !finalKey.isEmpty { try KeychainStore.save(finalKey, account: "documentAPIKey.\(suffix)") }
        if preset == documentAIPreset { documentEndpoint = finalEndpoint; documentAPIKey = finalKey; documentModel = finalModel }
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
        normalizeTranslationProvider()
        if translationProvider == .deepl,
           deepLEnabled,
           addedTranslationServiceIDs.contains(ServiceEntry.deepl.id) { return .deepl }
        if translationProvider == .ai,
           enabledTranslationAIs.contains(translationAIPreset.rawValue),
           addedTranslationServiceIDs.contains(ServiceEntry.ai(translationAIPreset).id) { return .ai }
        return nil
    }

    private func normalizeTranslationProvider() {
        let currentIsValid: Bool
        if translationProvider == .deepl {
            currentIsValid = deepLEnabled && addedTranslationServiceIDs.contains(ServiceEntry.deepl.id)
        } else {
            currentIsValid = enabledTranslationAIs.contains(translationAIPreset.rawValue)
                && addedTranslationServiceIDs.contains(ServiceEntry.ai(translationAIPreset).id)
        }
        if currentIsValid { return }

        for entry in addedTranslationServices where isTranslationServiceEnabled(entry) {
            switch entry {
            case .deepl:
                translationProvider = .deepl
            case .ai(let preset):
                translationAIPreset = preset
                translationProvider = .ai
                aiTranslationEnabled = true
                let suffix = profileSuffix(preset)
                translationEndpoint = UserDefaults.standard.string(forKey: "translationEndpoint.\(suffix)") ?? preset.endpoint
                translationModel = UserDefaults.standard.string(forKey: "translationModel.\(suffix)") ?? preset.suggestedModel
                translationAPIKey = KeychainStore.read(account: "translationAPIKey.\(suffix)")
            }
            persistTranslationPreferences()
            return
        }
        aiTranslationEnabled = false
        if !deepLEnabled { translationProvider = .ai }
        persistTranslationPreferences()
    }

    private func persistTranslationPreferences() {
        UserDefaults.standard.set(translationProvider.rawValue, forKey: "translationProvider")
        UserDefaults.standard.set(aiTranslationEnabled, forKey: "aiTranslationEnabled")
        UserDefaults.standard.set(deepLEnabled, forKey: "deepLEnabled")
        UserDefaults.standard.set(Array(enabledTranslationAIs), forKey: "enabledTranslationAIs")
        UserDefaults.standard.set(addedTranslationServiceIDs, forKey: "addedTranslationServiceIDs")
    }


    private func saveTranslationAIProfile(_ preset: AIProviderPreset) throws {
        let suffix = profileSuffix(preset)
        UserDefaults.standard.set(translationEndpoint, forKey: "translationEndpoint.\(suffix)")
        UserDefaults.standard.set(translationModel, forKey: "translationModel.\(suffix)")
        if !translationAPIKey.isEmpty { try KeychainStore.save(translationAPIKey, account: "translationAPIKey.\(suffix)") }
    }

    private func saveWritingAIProfile(_ preset: AIProviderPreset) throws {
        let suffix = profileSuffix(preset)
        UserDefaults.standard.set(writingEndpoint, forKey: "writingEndpoint.\(suffix)")
        UserDefaults.standard.set(writingModel, forKey: "writingModel.\(suffix)")
        if !writingAPIKey.isEmpty { try KeychainStore.save(writingAPIKey, account: "writingAPIKey.\(suffix)") }
    }

    private func migrateServiceListsIfNeeded() {
        if addedTranslationServiceIDs.isEmpty {
            addedTranslationServiceIDs = enabledTranslationAIs.map { ServiceEntry.ai(AIProviderPreset(rawValue: $0) ?? .openAI).id }.sorted()
            if deepLEnabled { addedTranslationServiceIDs.append(ServiceEntry.deepl.id) }
            if addedTranslationServiceIDs.isEmpty { addedTranslationServiceIDs = [ServiceEntry.ai(.openAI).id] }
        }
        if addedWritingServiceIDs.isEmpty {
            addedWritingServiceIDs = [ServiceEntry.ai(writingAIPreset).id]
            enabledWritingAIs = [writingAIPreset.rawValue]
        }
        let translationSuffix = profileSuffix(translationAIPreset)
        if UserDefaults.standard.string(forKey: "translationEndpoint.\(translationSuffix)") == nil {
            UserDefaults.standard.set(translationEndpoint, forKey: "translationEndpoint.\(translationSuffix)")
            UserDefaults.standard.set(translationModel, forKey: "translationModel.\(translationSuffix)")
            if let key = try? KeychainStore.readValue(account: "translationAPIKey"), !key.isEmpty { try? KeychainStore.save(key, account: "translationAPIKey.\(translationSuffix)") }
        }
        let writingSuffix = profileSuffix(writingAIPreset)
        if UserDefaults.standard.string(forKey: "writingEndpoint.\(writingSuffix)") == nil {
            UserDefaults.standard.set(writingEndpoint, forKey: "writingEndpoint.\(writingSuffix)")
            UserDefaults.standard.set(writingModel, forKey: "writingModel.\(writingSuffix)")
            if let key = try? KeychainStore.readValue(account: "writingAPIKey"), !key.isEmpty { try? KeychainStore.save(key, account: "writingAPIKey.\(writingSuffix)") }
        }
    }

    private func migrateDocumentServiceListIfNeeded() {
        guard addedDocumentServiceIDs.isEmpty else { return }
        if documentEngineMode == .deepl {
            addedDocumentServiceIDs = [ServiceEntry.deepl.id]; documentDeepLEnabled = true
        } else {
            addedDocumentServiceIDs = [ServiceEntry.ai(documentAIPreset).id]; enabledDocumentAIs.insert(documentAIPreset.rawValue)
        }
        try? saveSettings()
    }

    private func reloadSecretsWithRetry(force: Bool = false) async {
        let delays: [UInt64] = [0, 250_000_000, 750_000_000]
        for delay in delays {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            keychainIssue = nil
            let translationAccount = "translationAPIKey.\(profileSuffix(translationAIPreset))"
            let writingAccount = "writingAPIKey.\(profileSuffix(writingAIPreset))"
            if force || translationAPIKey.isEmpty, let value = readSecretPreservingFailure(translationAccount), !value.isEmpty { translationAPIKey = value }
            if force || writingAPIKey.isEmpty, let value = readSecretPreservingFailure(writingAccount), !value.isEmpty { writingAPIKey = value }
            if force || deepLAPIKey.isEmpty, let value = readSecretPreservingFailure("deepLAPIKey"), !value.isEmpty { deepLAPIKey = value }
            if force || documentAPIKey.isEmpty, let value = readSecretPreservingFailure("documentAPIKey"), !value.isEmpty { documentAPIKey = value }
            if keychainIssue == nil { return }
        }
    }

    private func readSecretPreservingFailure(_ account: String) -> String? {
        do { return try KeychainStore.readValue(account: account) }
        catch KeychainStore.KeychainError.status(let status) {
            if status == errSecItemNotFound { return nil }
            keychainIssue = "钥匙串暂时不可访问（\(status)）"
            return nil
        } catch { keychainIssue = error.localizedDescription; return nil }
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
