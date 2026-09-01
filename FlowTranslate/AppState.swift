import AppKit
import AVFoundation
import Foundation
import ServiceManagement

private final class SpeechObserver: NSObject, AVSpeechSynthesizerDelegate {
    var didFinish: (() -> Void)?
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { didFinish?() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { didFinish?() }
}

@MainActor
@Observable
final class AppState {
    let liveCaption = LiveCaptionModel()
    var mode: WorkMode = .translate
    var sourceLanguage = Language.supported[0]
    var targetLanguage = Language.supported[1]
    var crossWritingSourceLanguage = Language.supported.first(where: { $0.code == (UserDefaults.standard.string(forKey: "crossWritingSourceLanguage") ?? "zh-Hans") }) ?? Language.supported[1]
    var crossWritingTargetLanguage = Language.supported.first(where: { $0.code == (UserDefaults.standard.string(forKey: "crossWritingTargetLanguage") ?? "en") }) ?? Language.supported[3]
    var input = ""
    var output = ""
    var isWorking = false
    var processingStatus = ""
    var translationSummary = ""
    var isSummarizing = false
    var summaryError: String?
    var errorMessage: String?
    var keychainIssue: String?
    var history: [HistoryItem] = []

    var translationEndpoint = UserDefaults.standard.string(forKey: "translationEndpoint") ?? "https://api.openai.com/v1/chat/completions"
    var translationModel = UserDefaults.standard.string(forKey: "translationModel") ?? "gpt-4.1-mini"
    var translationAPIKey = ""
    var writingEndpoint = UserDefaults.standard.string(forKey: "writingEndpoint") ?? "https://api.openai.com/v1/chat/completions"
    var writingModel = UserDefaults.standard.string(forKey: "writingModel") ?? "gpt-4.1-mini"
    var writingAPIKey = ""
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
    var documentAPIKey = ""
    var addedDocumentServiceIDs = UserDefaults.standard.stringArray(forKey: "addedDocumentServiceIDs") ?? []
    var enabledDocumentAIs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "enabledDocumentAIs") ?? [])
    var documentDeepLEnabled = UserDefaults.standard.object(forKey: "documentDeepLEnabled") as? Bool ?? false
    var liveCaptionEngineMode = LiveCaptionEngineMode(rawValue: UserDefaults.standard.string(forKey: "liveCaptionEngineMode") ?? "") ?? .shared
    var liveCaptionAIPreset = AIProviderPreset(rawValue: UserDefaults.standard.string(forKey: "liveCaptionAIPreset") ?? "") ?? .openAI
    var liveCaptionEndpoint = UserDefaults.standard.string(forKey: "liveCaptionEndpoint") ?? AIProviderPreset.openAI.endpoint
    var liveCaptionModel = UserDefaults.standard.string(forKey: "liveCaptionModel") ?? AIProviderPreset.openAI.suggestedModel
    var liveCaptionAPIKey = ""
    var liveCaptionDeepLKey = ""
    var addedLiveCaptionServiceIDs = UserDefaults.standard.stringArray(forKey: "addedLiveCaptionServiceIDs") ?? [ServiceEntry.system.id]
    var enabledLiveCaptionAIs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "enabledLiveCaptionAIs") ?? [])
    var liveCaptionDeepLEnabled = UserDefaults.standard.object(forKey: "liveCaptionDeepLEnabled") as? Bool ?? false
    var appLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
    var deepLAPIKey = ""
    var deepLAPIType = DeepLAPIType(rawValue: UserDefaults.standard.string(forKey: "deepLAPIType") ?? "") ?? .free
    var deepLFormality = DeepLFormality(rawValue: UserDefaults.standard.string(forKey: "deepLFormality") ?? "") ?? .default
    var validationMessage = ""
    var isValidating = false
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var editorFontSize = UserDefaults.standard.object(forKey: "editorFontSize") as? Double ?? 16
    var editorLineSpacing = UserDefaults.standard.object(forKey: "editorLineSpacing") as? Double ?? 5
    var selectedVoiceIdentifier = UserDefaults.standard.string(forKey: "selectedVoiceIdentifier") ?? ""
    var isSpeaking = false
    var shortcuts: [ShortcutAction: ShortcutConfig] = AppState.loadShortcuts()

    private let service = AIService()
    private let deepLService = DeepLService()
    private let systemTranslationService = SystemTranslationService()
    @ObservationIgnored private let speechSynthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let speechObserver = SpeechObserver()
    private let historyURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "FlowTranslate/history.json")
    }()

    init() {
        speechObserver.didFinish = { [weak self] in Task { @MainActor in self?.isSpeaking = false } }
        speechSynthesizer.delegate = speechObserver
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
        translationSummary = ""; summaryError = nil
        let isTranslation = mode == .translate
        let effectiveSource = mode == .crossLanguageWriting ? crossWritingSourceLanguage : sourceLanguage
        let effectiveTarget = mode == .crossLanguageWriting ? crossWritingTargetLanguage : targetLanguage
        await reloadSecretsWithRetry(scope: .currentWork)
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
        if isTranslation && activeProvider == .system {
            isWorking = true; processingStatus = "正在使用 Apple 系统翻译…"; output = ""; errorMessage = nil
            do {
                let result = try await systemTranslationService.translate(text: cleaned, source: sourceLanguage, target: targetLanguage)
                output = result
                history.insert(.init(mode: mode, source: cleaned, result: result, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage), at: 0)
                saveHistory()
            } catch { errorMessage = error.localizedDescription }
            isWorking = false; processingStatus = ""
            return
        }
        if isTranslation && activeProvider == .ai && !aiTranslationEnabled { errorMessage = "AI 翻译服务尚未启用。"; return }
        if !isTranslation && !writingUsesTranslationEngine && !writingEnabled { errorMessage = "AI 文本处理服务尚未启用。"; return }
        if !isTranslation && writingUsesTranslationEngine && activeProvider != .ai {
            errorMessage = "当前文本翻译引擎不支持 AI 文本处理，请选择一个 AI 引擎。"
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

    func switchMode(to newMode: WorkMode) {
        guard mode != newMode else { return }
        mode = newMode
        clearWorkspace()
    }

    func clearWorkspace() {
        input = ""; output = ""; translationSummary = ""
        errorMessage = nil; summaryError = nil; processingStatus = ""
    }

    func summarizeTranslation() async {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .translate, !text.isEmpty else { return }
        await reloadSecretsWithRetry(scope: writingUsesTranslationEngine ? .translation : .writing)
        let sharesTranslationAI = writingUsesTranslationEngine
        if sharesTranslationAI && resolvedTranslationProvider() != .ai {
            summaryError = "当前文本翻译引擎不支持总结，请在 AI 文本处理中选择 AI 引擎。"; return
        }
        if !sharesTranslationAI && (!writingEnabled || !enabledWritingAIs.contains(writingAIPreset.rawValue)) {
            summaryError = "请先在 AI 文本处理中启用并配置总结使用的 AI 引擎。"; return
        }
        let endpoint = sharesTranslationAI ? translationEndpoint : writingEndpoint
        let preset = sharesTranslationAI ? translationAIPreset : writingAIPreset
        let storedKey = sharesTranslationAI ? translationAPIKey : writingAPIKey
        let model = sharesTranslationAI ? translationModel : writingModel
        let key = storedKey.isEmpty && preset == .ollama ? "ollama" : storedKey
        guard let url = URL(string: endpoint), !key.isEmpty, !model.isEmpty else { summaryError = ServiceError.invalidConfiguration.localizedDescription; return }
        isSummarizing = true; translationSummary = ""; summaryError = nil
        do {
            translationSummary = try await service.perform(text: text, mode: .summarize, source: targetLanguage, target: targetLanguage,
                                                             configuration: .init(endpoint: url, apiKey: key, model: model))
        } catch { summaryError = error.localizedDescription }
        isSummarizing = false
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
        utterance.voice = selectedVoiceIdentifier.isEmpty ? AVSpeechSynthesisVoice(language: code) : AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        speechSynthesizer.speak(utterance)
    }

    func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }

    func setSpeechVoice(_ identifier: String) {
        selectedVoiceIdentifier = identifier
        UserDefaults.standard.set(identifier, forKey: "selectedVoiceIdentifier")
        stopSpeaking()
    }

    func toggleSpeechPreview() {
        if isSpeaking { stopSpeaking(); return }
        let voice = selectedVoiceIdentifier.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
        let language = voice?.language.lowercased() ?? Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        let sample: String
        if language.hasPrefix("zh") { sample = "你好，这是 PallasOwl 的语音试听。" }
        else if language.hasPrefix("ja") { sample = "こんにちは、PallasOwl の音声サンプルです。" }
        else if language.hasPrefix("ko") { sample = "안녕하세요. PallasOwl 음성 미리 듣기입니다." }
        else if language.hasPrefix("fr") { sample = "Bonjour, voici un aperçu de la voix PallasOwl." }
        else { sample = "Hello, this is a preview of the PallasOwl voice." }
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: sample)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
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
        UserDefaults.standard.set(liveCaptionEngineMode.rawValue, forKey: "liveCaptionEngineMode")
        UserDefaults.standard.set(liveCaptionAIPreset.rawValue, forKey: "liveCaptionAIPreset")
        UserDefaults.standard.set(liveCaptionEndpoint, forKey: "liveCaptionEndpoint")
        UserDefaults.standard.set(liveCaptionModel, forKey: "liveCaptionModel")
        UserDefaults.standard.set(addedLiveCaptionServiceIDs, forKey: "addedLiveCaptionServiceIDs")
        UserDefaults.standard.set(Array(enabledLiveCaptionAIs), forKey: "enabledLiveCaptionAIs")
        UserDefaults.standard.set(liveCaptionDeepLEnabled, forKey: "liveCaptionDeepLEnabled")
        UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")
        UserDefaults.standard.set(Array(enabledTranslationAIs), forKey: "enabledTranslationAIs")
        UserDefaults.standard.set(editorFontSize, forKey: "editorFontSize")
        UserDefaults.standard.set(editorLineSpacing, forKey: "editorLineSpacing")
        UserDefaults.standard.set(crossWritingSourceLanguage.code, forKey: "crossWritingSourceLanguage")
        UserDefaults.standard.set(crossWritingTargetLanguage.code, forKey: "crossWritingTargetLanguage")
        UserDefaults.standard.set(deepLAPIType.rawValue, forKey: "deepLAPIType")
        UserDefaults.standard.set(deepLFormality.rawValue, forKey: "deepLFormality")
        if !translationAPIKey.isEmpty { try KeychainStore.save(translationAPIKey, account: "translationAPIKey") }
        if !writingAPIKey.isEmpty { try KeychainStore.save(writingAPIKey, account: "writingAPIKey") }
        if !deepLAPIKey.isEmpty { try KeychainStore.save(deepLAPIKey, account: "deepLAPIKey") }
        if !documentAPIKey.isEmpty { try KeychainStore.save(documentAPIKey, account: "documentAPIKey") }
        if !liveCaptionAPIKey.isEmpty { try KeychainStore.save(liveCaptionAPIKey, account: "liveCaptionAPIKey") }
        if !liveCaptionDeepLKey.isEmpty { try KeychainStore.save(liveCaptionDeepLKey, account: "liveCaptionDeepLKey") }
        try saveTranslationAIProfile(translationAIPreset)
        try saveWritingAIProfile(writingAIPreset)
        try saveLiveCaptionAIProfile(liveCaptionAIPreset)
    }

    func selectTranslationProvider(_ provider: TranslationProvider) {
        translationProvider = provider
        if provider == .ai { aiTranslationEnabled = true }
        if provider == .deepl {
            deepLEnabled = true
            if deepLAPIKey.isEmpty { deepLAPIKey = readSecret("deepLAPIKey") }
        }
        persistTranslationPreferences()
    }

    func setTranslationServiceEnabled(_ provider: TranslationProvider, enabled: Bool) {
        if provider == .ai { aiTranslationEnabled = enabled }
        else if provider == .deepl {
            deepLEnabled = enabled
            if enabled {
                enabledTranslationAIs.removeAll(); aiTranslationEnabled = false; translationProvider = .deepl
                if deepLAPIKey.isEmpty { deepLAPIKey = readSecret("deepLAPIKey") }
            }
        }
        normalizeTranslationProvider()
        persistTranslationPreferences()
    }

    func validateAI(writing: Bool) async {
        isValidating = true; validationMessage = "正在验证…"
        await reloadSecretsWithRetry(scope: writing && !writingUsesTranslationEngine ? .writing : .translation)
        let shared = writing && writingUsesTranslationEngine
        if shared && resolvedTranslationProvider() != .ai {
            validationMessage = "验证失败：当前文本翻译引擎不支持 AI 文本处理。"
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
        setTranslationServiceEnabled(entry, enabled: true)
        persistTranslationPreferences()
    }

    func removeTranslationService(_ entry: ServiceEntry) {
        addedTranslationServiceIDs.removeAll { $0 == entry.id }
        if case .ai(let preset) = entry { enabledTranslationAIs.remove(preset.rawValue) }
        if case .deepl = entry { deepLEnabled = false }
        aiTranslationEnabled = !enabledTranslationAIs.isEmpty
        normalizeTranslationProvider()
        if let next = addedTranslationServices.first(where: { isTranslationServiceEnabled($0) }) { activateTranslationService(next) }
        persistTranslationPreferences()
    }

    func activateTranslationService(_ entry: ServiceEntry) {
        switch entry {
        case .system: translationProvider = .system
        case .ai(let preset): selectTranslationAI(preset)
        case .deepl: selectTranslationProvider(.deepl)
        }
    }

    func isTranslationServiceEnabled(_ entry: ServiceEntry) -> Bool {
        switch entry { case .system: translationProvider == .system; case .ai(let preset): enabledTranslationAIs.contains(preset.rawValue); case .deepl: deepLEnabled }
    }

    func setTranslationServiceEnabled(_ entry: ServiceEntry, enabled: Bool) {
        switch entry {
        case .system:
            if enabled { enabledTranslationAIs.removeAll(); deepLEnabled = false; translationProvider = .system }
            else if translationProvider == .system { translationProvider = .ai }
        case .ai(let preset): setTranslationAIEnabled(preset, enabled: enabled)
        case .deepl: setTranslationServiceEnabled(TranslationProvider.deepl, enabled: enabled)
        }
        persistTranslationPreferences()
    }

    func isCurrentTranslationService(_ entry: ServiceEntry) -> Bool {
        switch entry {
        case .system: translationProvider == .system
        case .ai(let preset): translationProvider == .ai && translationAIPreset == preset && isTranslationAIEnabled(preset)
        case .deepl: translationProvider == .deepl && deepLEnabled
        }
    }

    func addWritingService(_ preset: AIProviderPreset) {
        let entry = ServiceEntry.ai(preset)
        guard !addedWritingServiceIDs.contains(entry.id) else { return }
        addedWritingServiceIDs.append(entry.id)
        enabledWritingAIs = [preset.rawValue]
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
        if enabled { enabledWritingAIs = [preset.rawValue]; selectWritingAI(preset) }
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

    func fetchOfficialModels(_ preset: AIProviderPreset, endpoint: String, apiKey: String) async throws -> [String] {
        let effectiveKey = apiKey.isEmpty && preset == .ollama ? "ollama" : apiKey
        guard !endpoint.isEmpty, !effectiveKey.isEmpty else { throw ServiceError.invalidConfiguration }
        let models = try await service.listModels(preset: preset, endpoint: endpoint, apiKey: effectiveKey)
        guard !models.isEmpty else { throw ServiceError.requestFailed("官方接口没有返回可用的文本模型") }
        UserDefaults.standard.set(models, forKey: "availableModels.\(profileSuffix(preset))")
        return models
    }

    func cachedModels(_ preset: AIProviderPreset) -> [String] {
        UserDefaults.standard.stringArray(forKey: "availableModels.\(profileSuffix(preset))") ?? []
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
            enabledTranslationAIs = [preset.rawValue]
            deepLEnabled = false
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
        if documentAPIKey.isEmpty { documentAPIKey = readSecret("documentAPIKey") }
        if liveCaptionAPIKey.isEmpty { liveCaptionAPIKey = readSecret("liveCaptionAPIKey.\(profileSuffix(liveCaptionAIPreset))") }
        if liveCaptionDeepLKey.isEmpty { liveCaptionDeepLKey = readSecret("liveCaptionDeepLKey") }
    }

    func reloadSecretsAfterUnlock() {
        guard keychainIssue != nil || translationAPIKey.isEmpty || writingAPIKey.isEmpty || deepLAPIKey.isEmpty else { return }
        Task { await reloadSecretsWithRetry(scope: .currentWork) }
    }

    func translateDocumentChunk(_ text: String, source: Language, target: Language) async throws -> String {
        await reloadSecretsWithRetry(scope: .document)
        let provider: TranslationProvider
        switch documentEngineMode {
        case .shared:
            guard let current = resolvedTranslationProvider() else { throw ServiceError.invalidConfiguration }
            provider = current
        case .sharedWriting:
            if writingUsesTranslationEngine {
                guard resolvedTranslationProvider() == .ai else { throw ServiceError.invalidConfiguration }
            } else {
                guard writingEnabled, enabledWritingAIs.contains(writingAIPreset.rawValue) else { throw ServiceError.invalidConfiguration }
            }
            provider = .ai
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
        if provider == .system {
            return try await systemTranslationService.translate(text: text, source: source, target: target)
        }
        let sharesTranslation = documentEngineMode == .shared || (documentEngineMode == .sharedWriting && writingUsesTranslationEngine)
        let sharesWriting = documentEngineMode == .sharedWriting && !writingUsesTranslationEngine
        let preset = sharesTranslation ? translationAIPreset : (sharesWriting ? writingAIPreset : documentAIPreset)
        let endpoint = sharesTranslation ? translationEndpoint : (sharesWriting ? writingEndpoint : documentEndpoint)
        let model = sharesTranslation ? translationModel : (sharesWriting ? writingModel : documentModel)
        let storedKey = sharesTranslation ? translationAPIKey : (sharesWriting ? writingAPIKey : documentAPIKey)
        let key = storedKey.isEmpty && preset == .ollama ? "ollama" : storedKey
        guard let url = URL(string: endpoint), !model.isEmpty, !key.isEmpty else { throw ServiceError.invalidConfiguration }
        return try await service.perform(text: text, mode: .translate, source: source, target: target,
                                         configuration: .init(endpoint: url, apiKey: key, model: model))
    }

    func translateLiveCaption(_ text: String, source: Language, target: Language) async throws -> String {
        await reloadSecretsWithRetry(scope: .liveCaption)
        if liveCaptionEngineMode == .shared { return try await translateUsingCurrentTextEngine(text, source: source, target: target) }
        if liveCaptionEngineMode == .system { return try await systemTranslationService.translate(text: text, source: source, target: target) }
        if liveCaptionEngineMode == .deepl {
            guard liveCaptionDeepLEnabled, !liveCaptionDeepLKey.isEmpty else { throw ServiceError.invalidConfiguration }
            return try await deepLService.translate(text: text, target: target, apiKey: liveCaptionDeepLKey, apiType: deepLAPIType, formality: deepLFormality)
        }
        let key = liveCaptionAPIKey.isEmpty && liveCaptionAIPreset == .ollama ? "ollama" : liveCaptionAPIKey
        guard enabledLiveCaptionAIs.contains(liveCaptionAIPreset.rawValue), let url = URL(string: liveCaptionEndpoint), !liveCaptionModel.isEmpty, !key.isEmpty else { throw ServiceError.invalidConfiguration }
        return try await service.perform(text: text, mode: .translate, source: source, target: target,
                                         configuration: .init(endpoint: url, apiKey: key, model: liveCaptionModel))
    }

    func translateInstantSelection(_ text: String) async throws -> String {
        await reloadSecretsWithRetry(scope: .translation)
        let automatic = Language.supported.first(where: { $0.code == "auto" }) ?? sourceLanguage
        return try await translateUsingCurrentTextEngine(text, source: automatic, target: targetLanguage)
    }

    private func translateUsingCurrentTextEngine(_ text: String, source: Language, target: Language) async throws -> String {
        guard let provider = resolvedTranslationProvider() else { throw ServiceError.invalidConfiguration }
        if provider == .system { return try await systemTranslationService.translate(text: text, source: source, target: target) }
        if provider == .deepl { return try await deepLService.translate(text: text, target: target, apiKey: deepLAPIKey, apiType: deepLAPIType, formality: deepLFormality) }
        let key = translationAPIKey.isEmpty && translationAIPreset == .ollama ? "ollama" : translationAPIKey
        guard let url = URL(string: translationEndpoint), !translationModel.isEmpty, !key.isEmpty else { throw ServiceError.invalidConfiguration }
        return try await service.perform(text: text, mode: .translate, source: source, target: target,
                                         configuration: .init(endpoint: url, apiKey: key, model: translationModel))
    }

    var addedLiveCaptionServices: [ServiceEntry] { addedLiveCaptionServiceIDs.compactMap(ServiceEntry.from(id:)) }

    func addLiveCaptionService(_ entry: ServiceEntry) {
        guard !addedLiveCaptionServiceIDs.contains(entry.id) else { return }
        addedLiveCaptionServiceIDs.append(entry.id); setLiveCaptionServiceEnabled(entry, enabled: true)
    }

    func removeLiveCaptionService(_ entry: ServiceEntry) {
        addedLiveCaptionServiceIDs.removeAll { $0 == entry.id }
        if case .ai(let preset) = entry { enabledLiveCaptionAIs.remove(preset.rawValue) }
        if case .deepl = entry { liveCaptionDeepLEnabled = false }
        if case .system = entry, liveCaptionEngineMode == .system { liveCaptionEngineMode = .shared }
        try? saveSettings()
    }

    func isLiveCaptionServiceEnabled(_ entry: ServiceEntry) -> Bool {
        switch entry { case .system: liveCaptionEngineMode == .system; case .ai(let preset): liveCaptionEngineMode == .ai && enabledLiveCaptionAIs.contains(preset.rawValue); case .deepl: liveCaptionEngineMode == .deepl && liveCaptionDeepLEnabled }
    }

    func setLiveCaptionServiceEnabled(_ entry: ServiceEntry, enabled: Bool) {
        let wasEnabled = isLiveCaptionServiceEnabled(entry)
        if enabled {
            enabledLiveCaptionAIs.removeAll(); liveCaptionDeepLEnabled = false
            switch entry {
            case .system: liveCaptionEngineMode = .system
            case .deepl:
                liveCaptionEngineMode = .deepl; liveCaptionDeepLEnabled = true
                if liveCaptionDeepLKey.isEmpty { liveCaptionDeepLKey = readSecret("liveCaptionDeepLKey") }
            case .ai(let preset): liveCaptionEngineMode = .ai; enabledLiveCaptionAIs = [preset.rawValue]; selectLiveCaptionAI(preset)
            }
        } else {
            if case .ai(let preset) = entry { enabledLiveCaptionAIs.remove(preset.rawValue) }
            if case .deepl = entry { liveCaptionDeepLEnabled = false }
            if wasEnabled { liveCaptionEngineMode = .shared }
        }
        try? saveSettings()
    }

    func selectLiveCaptionAI(_ preset: AIProviderPreset) {
        try? saveLiveCaptionAIProfile(liveCaptionAIPreset)
        liveCaptionAIPreset = preset
        let suffix = profileSuffix(preset)
        liveCaptionEndpoint = UserDefaults.standard.string(forKey: "liveCaptionEndpoint.\(suffix)") ?? preset.endpoint
        liveCaptionModel = UserDefaults.standard.string(forKey: "liveCaptionModel.\(suffix)") ?? preset.suggestedModel
        liveCaptionAPIKey = KeychainStore.read(account: "liveCaptionAPIKey.\(suffix)")
        try? saveSettings()
    }

    func saveLiveCaptionAIProfile(_ preset: AIProviderPreset) throws {
        let suffix = profileSuffix(preset)
        UserDefaults.standard.set(liveCaptionEndpoint, forKey: "liveCaptionEndpoint.\(suffix)")
        UserDefaults.standard.set(liveCaptionModel, forKey: "liveCaptionModel.\(suffix)")
        if !liveCaptionAPIKey.isEmpty { try KeychainStore.save(liveCaptionAPIKey, account: "liveCaptionAPIKey.\(suffix)") }
    }

    func validateLiveCaptionEngine() async {
        isValidating = true; validationMessage = "正在验证…"
        do {
            switch liveCaptionEngineMode {
            case .shared: validationMessage = "验证成功：将使用文本翻译当前引擎"
            case .system: validationMessage = "验证成功：Apple 系统翻译无需 API Key"
            case .deepl: validationMessage = try await deepLService.validate(apiKey: liveCaptionDeepLKey, apiType: deepLAPIType)
            case .ai:
                let key = liveCaptionAPIKey.isEmpty && liveCaptionAIPreset == .ollama ? "ollama" : liveCaptionAPIKey
                guard let url = URL(string: liveCaptionEndpoint) else { throw ServiceError.invalidConfiguration }
                validationMessage = try await service.validate(configuration: .init(endpoint: url, apiKey: key, model: liveCaptionModel))
            }
        } catch { validationMessage = "验证失败：\(error.localizedDescription)" }
        isValidating = false
    }

    var documentCurrentServiceName: String {
        switch documentEngineMode {
        case .shared:
            switch translationProvider {
            case .system: return "Apple 系统翻译"
            case .deepl: return "DeepL 翻译"
            case .ai: return translationAIPreset.rawValue
            }
        case .sharedWriting:
            if !writingUsesTranslationEngine { return writingAIPreset.rawValue }
            switch translationProvider {
            case .system: return "Apple 系统翻译"
            case .deepl: return "DeepL 翻译"
            case .ai: return translationAIPreset.rawValue
            }
        case .ai: return documentAIPreset.rawValue
        case .deepl: return "DeepL 翻译"
        }
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
        case .system: return
        case .ai(let preset): documentEngineMode = .ai; applyDocumentAIPreset(preset)
        case .deepl:
            documentEngineMode = .deepl
            if deepLAPIKey.isEmpty { deepLAPIKey = readSecret("deepLAPIKey") }
        }
        try? saveSettings()
    }

    func isDocumentServiceEnabled(_ entry: ServiceEntry) -> Bool {
        switch entry { case .system: false; case .ai(let preset): enabledDocumentAIs.contains(preset.rawValue); case .deepl: documentDeepLEnabled }
    }

    func setDocumentServiceEnabled(_ entry: ServiceEntry, enabled: Bool) {
        switch entry {
        case .system: break
        case .ai(let preset): if enabled { enabledDocumentAIs = [preset.rawValue]; documentDeepLEnabled = false } else { enabledDocumentAIs.remove(preset.rawValue) }
        case .deepl: documentDeepLEnabled = enabled; if enabled { enabledDocumentAIs.removeAll() }
        }
        if enabled { activateDocumentService(entry) }
        else if isCurrentDocumentService(entry), let next = addedDocumentServices.first(where: isDocumentServiceEnabled) { activateDocumentService(next) }
        try? saveSettings()
    }

    func isCurrentDocumentService(_ entry: ServiceEntry) -> Bool {
        switch entry {
        case .system: false
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
        clearWorkspace()
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
        if translationProvider == .system,
           addedTranslationServiceIDs.contains(ServiceEntry.system.id) { return .system }
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
        if translationProvider == .system {
            currentIsValid = addedTranslationServiceIDs.contains(ServiceEntry.system.id)
        } else if translationProvider == .deepl {
            currentIsValid = deepLEnabled && addedTranslationServiceIDs.contains(ServiceEntry.deepl.id)
        } else {
            currentIsValid = enabledTranslationAIs.contains(translationAIPreset.rawValue)
                && addedTranslationServiceIDs.contains(ServiceEntry.ai(translationAIPreset).id)
        }
        if currentIsValid { return }

        for entry in addedTranslationServices where isTranslationServiceEnabled(entry) {
            switch entry {
            case .system:
                translationProvider = .system
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
        if !addedTranslationServiceIDs.contains(ServiceEntry.system.id) {
            addedTranslationServiceIDs.insert(ServiceEntry.system.id, at: 0)
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

    private enum SecretScope { case currentWork, translation, writing, document, liveCaption }

    private func reloadSecretsWithRetry(scope: SecretScope, force: Bool = false) async {
        let delays: [UInt64] = [0, 250_000_000, 750_000_000]
        for delay in delays {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            keychainIssue = nil
            let translationAccount = "translationAPIKey.\(profileSuffix(translationAIPreset))"
            let writingAccount = "writingAPIKey.\(profileSuffix(writingAIPreset))"
            let effectiveScope: SecretScope = scope == .currentWork
                ? (mode == .translate ? .translation : (writingUsesTranslationEngine ? .translation : .writing))
                : scope
            switch effectiveScope {
            case .translation:
                if resolvedTranslationProvider() == .deepl {
                    if force || deepLAPIKey.isEmpty, let value = readSecretPreservingFailure("deepLAPIKey"), !value.isEmpty { deepLAPIKey = value }
                } else if resolvedTranslationProvider() == .ai, force || translationAPIKey.isEmpty,
                          let value = readSecretPreservingFailure(translationAccount), !value.isEmpty { translationAPIKey = value }
            case .writing:
                if force || writingAPIKey.isEmpty, let value = readSecretPreservingFailure(writingAccount), !value.isEmpty { writingAPIKey = value }
            case .document:
                if documentEngineMode == .shared { await reloadSecretsWithRetry(scope: .translation, force: force); return }
                if documentEngineMode == .sharedWriting { await reloadSecretsWithRetry(scope: writingUsesTranslationEngine ? .translation : .writing, force: force); return }
                if documentEngineMode == .deepl {
                    if force || deepLAPIKey.isEmpty, let value = readSecretPreservingFailure("deepLAPIKey"), !value.isEmpty { deepLAPIKey = value }
                } else if force || documentAPIKey.isEmpty,
                          let value = readSecretPreservingFailure("documentAPIKey.\(profileSuffix(documentAIPreset))"), !value.isEmpty { documentAPIKey = value }
            case .liveCaption:
                if liveCaptionEngineMode == .shared { await reloadSecretsWithRetry(scope: .translation, force: force); return }
                if liveCaptionEngineMode == .deepl {
                    if force || liveCaptionDeepLKey.isEmpty, let value = readSecretPreservingFailure("liveCaptionDeepLKey"), !value.isEmpty { liveCaptionDeepLKey = value }
                } else if liveCaptionEngineMode == .ai, force || liveCaptionAPIKey.isEmpty,
                          let value = readSecretPreservingFailure("liveCaptionAPIKey.\(profileSuffix(liveCaptionAIPreset))"), !value.isEmpty { liveCaptionAPIKey = value }
            case .currentWork: break
            }
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
        case .anthropic: "anthropic"
        case .gemini: "gemini"
        case .deepSeek: "deepseek"
        case .qwen: "qwen"
        case .kimi: "kimi"
        case .doubao: "doubao"
        case .zhipu: "zhipu"
        case .ernie: "ernie"
        case .hunyuan: "hunyuan"
        case .minimax: "minimax"
        case .siliconFlow: "siliconflow"
        case .xAI: "xai"
        case .groq: "groq"
        case .openRouter: "openrouter"
        case .perplexity: "perplexity"
        case .mistral: "mistral"
        case .cohere: "cohere"
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
