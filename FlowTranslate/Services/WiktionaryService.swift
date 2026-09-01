import AppKit
import Foundation

struct WiktionaryEntry: Sendable {
    let language: String
    let partOfSpeech: String
    let definition: String
    let example: String?
}

final class WiktionaryService: Sendable {
    private struct Meaning: Decodable {
        let partOfSpeech: String
        let language: String
        let definitions: [Definition]
    }
    private struct Definition: Decodable {
        let definition: String
        let examples: [String]?
    }

    func lookup(_ term: String) async throws -> WiktionaryEntry? {
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wiktionary.org/api/rest_v1/page/definition/\(encoded)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("PallasOwlTranslator/0.10 (+mailto:pallasowl2026@gmail.com)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let groups = try JSONDecoder().decode([String: [Meaning]].self, from: data)
        let preferred = groups["en"] ?? groups.values.first ?? []
        guard let meaning = preferred.first(where: { !$0.definitions.isEmpty }), let first = meaning.definitions.first else { return nil }
        return WiktionaryEntry(language: meaning.language,
                               partOfSpeech: meaning.partOfSpeech,
                               definition: Self.plainText(first.definition),
                               example: first.examples?.first.map(Self.plainText))
    }

    static func pageURL(for term: String) -> URL? {
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://en.wiktionary.org/wiki/\(encoded)")
    }

    private static func plainText(_ html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) else {
            return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
