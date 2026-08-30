import Foundation
import NaturalLanguage
import Translation

enum SystemTranslationError: LocalizedError {
    case requiresNewerSystem
    case languageUnavailable

    var errorDescription: String? {
        switch self {
        case .requiresNewerSystem: "Apple 系统翻译需要 macOS 26 或更高版本。"
        case .languageUnavailable: "所选语言的系统翻译包尚未安装，请先在 macOS“系统设置 → 通用 → 语言与地区 → 翻译语言”中下载。"
        }
    }
}

actor SystemTranslationService {
    func translate(text: String, source: Language, target: Language) async throws -> String {
        guard #available(macOS 26.0, *) else { throw SystemTranslationError.requiresNewerSystem }
        let sourceCode = source.code == "auto" ? detectedLanguage(for: text) : source.code
        let sourceLanguage = Locale.Language(identifier: normalized(sourceCode))
        let targetLanguage = Locale.Language(identifier: normalized(target.code))
        let availability = LanguageAvailability()
        guard await availability.status(from: sourceLanguage, to: targetLanguage) == .installed else {
            throw SystemTranslationError.languageUnavailable
        }
        let session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        return try await session.translate(text).targetText
    }

    private func detectedLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }

    private func normalized(_ code: String) -> String {
        switch code {
        case "zh-Hans": "zh-Hans"
        case "zh-Hant": "zh-Hant"
        default: code
        }
    }
}
