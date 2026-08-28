import Foundation

actor DeepLService {
    func translate(text: String, target: Language, apiKey: String, apiType: DeepLAPIType, formality: DeepLFormality) async throws -> String {
        guard let url = URL(string: apiType.baseURL + "/v2/translate") else { throw ServiceError.invalidConfiguration }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["text": [text], "target_lang": deepLCode(target)]
        if let value = formality.apiValue { body["formality"] = value }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.requestFailed(decodeError(data) ?? "DeepL 服务验证失败")
        }
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard let text = result.translations.first?.text else { throw ServiceError.emptyResponse }
        return text
    }

    func validate(apiKey: String, apiType: DeepLAPIType) async throws -> String {
        guard !apiKey.isEmpty, let url = URL(string: apiType.baseURL + "/v2/usage") else { throw ServiceError.invalidConfiguration }
        var request = URLRequest(url: url)
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.requestFailed(decodeError(data) ?? "DeepL Key 无效")
        }
        let usage = try JSONDecoder().decode(Usage.self, from: data)
        return "验证成功 · 已用 \(usage.characterCount) / \(usage.characterLimit) 字符"
    }

    private func deepLCode(_ language: Language) -> String {
        switch language.code {
        case "zh-Hans", "zh-Hant": "ZH"
        case "en": "EN-US"
        default: language.code.uppercased()
        }
    }
    private func decodeError(_ data: Data) -> String? { (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.message }
    private struct Response: Decodable { struct Translation: Decodable { let text: String }; let translations: [Translation] }
    private struct Usage: Decodable { let characterCount: Int; let characterLimit: Int; enum CodingKeys: String, CodingKey { case characterCount = "character_count"; case characterLimit = "character_limit" } }
    private struct ErrorResponse: Decodable { let message: String }
}
