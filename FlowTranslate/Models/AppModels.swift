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
    case openLiveCaption = "打开实时字幕"
    case toggleLiveCaption = "开始/停止实时字幕"
    var id: Self { self }
    var defaultLetter: String {
        switch self { case .input: "A"; case .selection: "D"; case .screenshot: "S"; case .crossWriting: "W"; case .openLiveCaption: "L"; case .toggleLiveCaption: "R" }
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
    case anthropic = "Anthropic Claude"
    case gemini = "Google Gemini"
    case deepSeek = "DeepSeek"
    case qwen = "通义千问"
    case kimi = "Kimi"
    case doubao = "豆包"
    case zhipu = "智谱 GLM"
    case ernie = "百度文心"
    case hunyuan = "腾讯混元"
    case minimax = "MiniMax"
    case siliconFlow = "硅基流动"
    case xAI = "xAI Grok"
    case groq = "Groq"
    case openRouter = "OpenRouter"
    case perplexity = "Perplexity"
    case mistral = "Mistral AI"
    case cohere = "Cohere"
    case ollama = "Ollama（本地）"
    case custom = "自定义"
    var id: Self { self }
    var endpoint: String {
        switch self {
        case .openAI: "https://api.openai.com/v1/chat/completions"
        case .anthropic: "https://api.anthropic.com/v1/chat/completions"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .deepSeek: "https://api.deepseek.com/chat/completions"
        case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .kimi: "https://api.moonshot.cn/v1/chat/completions"
        case .doubao: "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        case .zhipu: "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        case .ernie: "https://qianfan.baidubce.com/v2/chat/completions"
        case .hunyuan: "https://api.hunyuan.cloud.tencent.com/v1/chat/completions"
        case .minimax: "https://api.minimax.chat/v1/text/chatcompletion_v2"
        case .siliconFlow: "https://api.siliconflow.cn/v1/chat/completions"
        case .xAI: "https://api.x.ai/v1/chat/completions"
        case .groq: "https://api.groq.com/openai/v1/chat/completions"
        case .openRouter: "https://openrouter.ai/api/v1/chat/completions"
        case .perplexity: "https://api.perplexity.ai/chat/completions"
        case .mistral: "https://api.mistral.ai/v1/chat/completions"
        case .cohere: "https://api.cohere.com/compatibility/v1/chat/completions"
        case .ollama: "http://localhost:11434/v1/chat/completions"
        case .custom: ""
        }
    }
    var suggestedModel: String {
        switch self {
        case .openAI: "gpt-4.1-mini"
        case .anthropic: "claude-sonnet-4-5"
        case .gemini: "gemini-3.7-flash"
        case .deepSeek: "deepseek-chat"
        case .qwen: "qwen-plus"
        case .kimi: "moonshot-v1-8k"
        case .doubao: "请填写推理接入点 ID"
        case .zhipu: "glm-4-flash"
        case .ernie: "ernie-4.5-turbo-32k"
        case .hunyuan: "hunyuan-turbos-latest"
        case .minimax: "MiniMax-M2"
        case .siliconFlow: "Qwen/Qwen3-8B"
        case .xAI: "grok-4-fast"
        case .groq: "llama-3.3-70b-versatile"
        case .openRouter: "openai/gpt-4.1-mini"
        case .perplexity: "sonar"
        case .mistral: "mistral-small-latest"
        case .cohere: "command-r-plus"
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
        .init(code: "es", name: "西班牙语"),
        .init(code: "pt", name: "葡萄牙语"),
        .init(code: "it", name: "意大利语"),
        .init(code: "ar", name: "阿拉伯语"),
        .init(code: "ru", name: "俄语"),
        .init(code: "vi", name: "越南语"),
        .init(code: "id", name: "印尼语"),
        .init(code: "th", name: "泰语")
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
    case system
    case ai(AIProviderPreset)
    case deepl

    var id: String {
        switch self { case .system: "system"; case .ai(let preset): "ai:\(preset.rawValue)"; case .deepl: "deepl" }
    }
    var name: String {
        switch self { case .system: "Apple 系统翻译"; case .ai(let preset): preset.rawValue; case .deepl: "DeepL 翻译" }
    }
    var icon: String {
        switch self { case .system: "apple.logo"; case .ai(.ollama): "desktopcomputer"; case .ai: "sparkles"; case .deepl: "character.bubble" }
    }
    var aiPreset: AIProviderPreset? {
        if case .ai(let preset) = self { return preset }
        return nil
    }
    static func from(id: String) -> Self? {
        if id == "system" { return .system }
        if id == "deepl" { return .deepl }
        guard id.hasPrefix("ai:"), let preset = AIProviderPreset(rawValue: String(id.dropFirst(3))) else { return nil }
        return .ai(preset)
    }
}

enum TranslationProvider: String, CaseIterable, Identifiable, Codable {
    case system = "Apple 系统翻译"
    case ai = "AI 翻译"
    case deepl = "DeepL 翻译"
    var id: Self { self }
    var icon: String { self == .system ? "apple.logo" : (self == .ai ? "sparkles" : "character.bubble") }
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

enum DocumentEngineMode: String, CaseIterable, Identifiable {
    case shared = "与文本翻译共用引擎"
    case sharedWriting = "与 AI 文本处理共用引擎"
    case ai = "独立 AI 引擎"
    case deepl = "独立 DeepL"
    var id: Self { self }
}

enum DocumentOutputStyle: String, CaseIterable, Identifiable {
    case translated = "仅译文"
    case bilingual = "原文与译文"
    var id: Self { self }
}

enum DocumentExportFormat: String, CaseIterable, Identifiable {
    case markdown = "Obsidian Markdown"
    case plainText = "纯文本"
    var id: Self { self }
    var fileExtension: String { self == .markdown ? "md" : "txt" }
}

enum LiveAudioSource: String, CaseIterable, Identifiable {
    case microphone = "麦克风"
    case allApplications = "全部应用"
    case application = "指定应用"
    var id: Self { self }
    var icon: String { self == .microphone ? "mic.fill" : (self == .application ? "app.fill" : "speaker.wave.2.fill") }
}

enum LiveCaptionEngineMode: String, CaseIterable, Identifiable {
    case shared = "与文本翻译共用引擎"
    case system = "Apple 系统翻译"
    case ai = "独立 AI 引擎"
    case deepl = "独立 DeepL"
    var id: Self { self }
}

enum LiveCaptionDisplayMode: String, CaseIterable, Identifiable {
    case bilingual = "原文与译文"
    case sourceOnly = "仅原文"
    case translationOnly = "仅译文"
    var id: Self { self }
}

struct DocumentTranslationSection: Identifiable, Sendable {
    let id = UUID()
    let source: String
    var translation: String
}
