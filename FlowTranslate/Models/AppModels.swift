import Foundation

enum WorkMode: String, CaseIterable, Identifiable, Codable {
    case translate = "翻译"
    case polish = "润色"
    case crossLanguageWriting = "跨语写作"
    case summarize = "总结"

    var id: Self { self }
    var systemIcon: String {
        switch self {
        case .translate: "character.book.closed"
        case .polish: "wand.and.stars"
        case .crossLanguageWriting: "pencil.and.scribble"
        case .summarize: "text.alignleft"
        }
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case input = "输入翻译"
    case selection = "划词翻译"
    case screenshot = "截图翻译"
    case crossWriting = "跨语写作并替换"
    var id: Self { self }
    var defaultLetter: String {
        switch self { case .input: "A"; case .selection: "D"; case .screenshot: "S"; case .crossWriting: "W" }
    }
}

struct ShortcutConfig: Codable, Hashable {
    var letter: String
    var control = true
    var option = true
    var shift = false
    var command = false

    var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + letter
    }

    static func defaultValue(for action: ShortcutAction) -> Self { .init(letter: action.defaultLetter) }
}

enum AIProviderPreset: String, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case gemini = "Google Gemini"
    case deepSeek = "DeepSeek"
    case groq = "Groq"
    case openRouter = "OpenRouter"
    case ollama = "Ollama（本地）"
    case custom = "自定义"
    var id: Self { self }
    var endpoint: String {
        switch self {
        case .openAI: "https://api.openai.com/v1/chat/completions"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .deepSeek: "https://api.deepseek.com/chat/completions"
        case .groq: "https://api.groq.com/openai/v1/chat/completions"
        case .openRouter: "https://openrouter.ai/api/v1/chat/completions"
        case .ollama: "http://localhost:11434/v1/chat/completions"
        case .custom: ""
        }
    }
    var suggestedModel: String {
        switch self {
        case .openAI: "gpt-4.1-mini"
        case .gemini: "gemini-3.7-flash"
        case .deepSeek: "deepseek-chat"
        case .groq: "llama-3.3-70b-versatile"
        case .openRouter: "openai/gpt-4.1-mini"
        case .ollama: "qwen3:8b"
        case .custom: ""
        }
    }
}

struct Language: Identifiable, Hashable, Codable {
    let code: String
    let name: String
    var id: String { code }

    static let supported: [Language] = [
        .init(code: "auto", name: "自动检测"),
        .init(code: "zh-Hans", name: "简体中文"),
        .init(code: "zh-Hant", name: "繁体中文"),
        .init(code: "en", name: "英语"),
        .init(code: "ja", name: "日语"),
        .init(code: "ko", name: "韩语"),
        .init(code: "fr", name: "法语"),
        .init(code: "de", name: "德语"),
        .init(code: "es", name: "西班牙语")
    ]
}

struct HistoryItem: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let mode: WorkMode
    let source: String
    let result: String
    let sourceLanguage: Language
    let targetLanguage: Language

    init(mode: WorkMode, source: String, result: String, sourceLanguage: Language, targetLanguage: Language) {
        id = UUID()
        createdAt = Date()
        self.mode = mode
        self.source = source
        self.result = result
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}

enum AIUsage: String, CaseIterable, Identifiable {
    case translation = "翻译 AI"
    case writing = "写作 AI"
    var id: Self { self }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case french = "fr"
    case japanese = "ja"

    var id: Self { self }
    var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        case .french: "Français"
        case .japanese: "日本語"
        }
    }
    var localeIdentifier: String? { self == .system ? nil : rawValue }
}

enum ServiceEntry: Hashable, Identifiable {
    case ai(AIProviderPreset)
    case deepl

    var id: String {
        switch self { case .ai(let preset): "ai:\(preset.rawValue)"; case .deepl: "deepl" }
    }
    var name: String {
        switch self { case .ai(let preset): preset.rawValue; case .deepl: "DeepL 翻译" }
    }
    var icon: String {
        switch self { case .ai(.ollama): "desktopcomputer"; case .ai: "sparkles"; case .deepl: "character.bubble" }
    }
    var aiPreset: AIProviderPreset? {
        if case .ai(let preset) = self { return preset }
        return nil
    }
    static func from(id: String) -> Self? {
        if id == "deepl" { return .deepl }
        guard id.hasPrefix("ai:"), let preset = AIProviderPreset(rawValue: String(id.dropFirst(3))) else { return nil }
        return .ai(preset)
    }
}

enum TranslationProvider: String, CaseIterable, Identifiable, Codable {
    case ai = "AI 翻译"
    case deepl = "DeepL 翻译"
    var id: Self { self }
    var icon: String { self == .ai ? "sparkles" : "character.bubble" }
}

enum DeepLAPIType: String, CaseIterable, Identifiable {
    case free = "DeepL API Free"
    case pro = "DeepL API Pro"
    var id: Self { self }
    var baseURL: String { self == .free ? "https://api-free.deepl.com" : "https://api.deepl.com" }
}

enum DeepLFormality: String, CaseIterable, Identifiable {
    case `default` = "默认"
    case more = "更正式"
    case less = "更口语"
    var id: Self { self }
    var apiValue: String? {
        switch self { case .default: nil; case .more: "more"; case .less: "less" }
    }
}
