import Foundation

struct AIConfiguration {
    let endpoint: URL
    let apiKey: String
    let model: String
}

actor AIService {
    func validate(configuration: AIConfiguration) async throws -> String {
        guard !configuration.apiKey.isEmpty else { throw ServiceError.invalidConfiguration }
        var text = configuration.endpoint.absoluteString
        if text.hasSuffix("/chat/completions") { text.removeLast("/chat/completions".count) }
        guard let url = URL(string: text + "/models") else { throw ServiceError.invalidConfiguration }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message)
            throw ServiceError.requestFailed(message ?? "AI 服务验证失败")
        }
        return "验证成功 · 服务可用"
    }

    func perform(
        text: String,
        mode: WorkMode,
        source: Language,
        target: Language,
        configuration: AIConfiguration
    ) async throws -> String {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        let instruction: String
        switch mode {
        case .translate:
            instruction = "Translate the user text from \(source.name) to \(target.name). Return only the translation, preserving formatting."
        case .polish:
            instruction = "Polish and correct the user text in its original language. Preserve meaning and formatting. Return only the improved text."
        case .crossLanguageWriting:
            instruction = "The user will express an intent, usually in Chinese. Rewrite it as natural, idiomatic, well-structured \(target.name) suitable for direct use. Do not translate literally. Return only the final text."
        case .summarize:
            instruction = "Summarize the user text concisely in \(target.name). Return only the summary."
        }

        let payload = ChatRequest(
            model: configuration.model,
            messages: [
                .init(role: "system", content: instruction),
                .init(role: "user", content: text)
            ]
        )
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message)
            throw ServiceError.requestFailed(message ?? "服务返回异常")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw ServiceError.emptyResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
}

private struct Message: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable { let message: Message }
    let choices: [Choice]
}

private struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}

enum ServiceError: LocalizedError {
    case invalidConfiguration
    case requestFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "请先在设置中填写有效的 API 配置。"
        case .requestFailed(let message): message
        case .emptyResponse: "服务没有返回内容。"
        }
    }
}
