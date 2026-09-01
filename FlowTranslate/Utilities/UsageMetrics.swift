import Foundation

enum UsageMetric: String, CaseIterable, Identifiable {
    case translation, polish, crossWriting, documentExtraction, documentTranslation
    case liveCaption, selectionTranslation, screenshotTranslation, instantSelection, dictionaryLookup
    var id: String { rawValue }
    var title: String {
        switch self {
        case .translation: "文本翻译"
        case .polish: "润色"
        case .crossWriting: "跨语写作"
        case .documentExtraction: "文档文字提取"
        case .documentTranslation: "文档翻译"
        case .liveCaption: "实时字幕"
        case .selectionTranslation: "划词翻译"
        case .screenshotTranslation: "截图翻译"
        case .instantSelection: "选中即译"
        case .dictionaryLookup: "词典查询"
        }
    }
}

enum UsageMetrics {
    private static let prefix = "usageCount."
    static func increment(_ metric: UsageMetric) {
        let key = prefix + metric.rawValue
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }
    static func count(_ metric: UsageMetric) -> Int { UserDefaults.standard.integer(forKey: prefix + metric.rawValue) }
    static func increment(_ mode: WorkMode) {
        switch mode {
        case .translate: increment(UsageMetric.translation)
        case .polish: increment(UsageMetric.polish)
        case .crossLanguageWriting: increment(UsageMetric.crossWriting)
        case .summarize: break
        }
    }
}
