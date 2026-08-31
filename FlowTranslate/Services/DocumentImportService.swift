import AppKit
import Foundation
import PDFKit
import Vision

enum DocumentImportError: LocalizedError {
    case unsupported
    case unreadable
    case noText

    var errorDescription: String? {
        switch self {
        case .unsupported: "暂不支持这种文件格式。"
        case .unreadable: "无法读取这个文件。"
        case .noText: "没有识别到可翻译的文字。"
        }
    }
}

struct DocumentImportService {
    func extractText(from url: URL, progress: @escaping @Sendable (Double, String) async -> Void) async throws -> String {
        let ext = url.pathExtension.lowercased()
        await progress(0.03, "正在读取文件…")
        let text: String
        switch ext {
        case "txt", "md", "markdown", "rtf", "rtfd", "doc", "docx":
            text = try extractRichText(from: url)
        case "pdf":
            text = try await extractPDF(from: url, progress: progress)
        case "png", "jpg", "jpeg", "heic", "tif", "tiff", "bmp":
            text = try await recognizeImage(at: url)
        default:
            throw DocumentImportError.unsupported
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw DocumentImportError.noText }
        return cleaned
    }

    func extractText(from image: NSImage) async throws -> String {
        let value = try await recognize(image: image).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw DocumentImportError.noText }
        return value
    }

    private func extractRichText(from url: URL) throws -> String {
        if ["txt", "md", "markdown"].contains(url.pathExtension.lowercased()) {
            if let value = try? String(contentsOf: url, encoding: .utf8) { return value }
            if let value = try? String(contentsOf: url, encoding: .unicode) { return value }
        }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.characterEncoding: String.Encoding.utf8.rawValue]
        guard let value = try? NSAttributedString(url: url, options: options, documentAttributes: nil) else {
            throw DocumentImportError.unreadable
        }
        return value.string
    }

    private func extractPDF(from url: URL, progress: @escaping @Sendable (Double, String) async -> Void) async throws -> String {
        guard let document = PDFDocument(url: url) else { throw DocumentImportError.unreadable }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            guard !Task.isCancelled else { throw CancellationError() }
            let page = document.page(at: index)
            var value = page?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.count < 20, let image = page?.thumbnail(of: CGSize(width: 2200, height: 3000), for: .mediaBox) {
                value = try await recognize(image: image)
            }
            if !value.isEmpty { pages.append(Self.normalizeExtractedText(value)) }
            await progress(0.05 + (Double(index + 1) / Double(max(document.pageCount, 1))) * 0.25, "正在解析第 \(index + 1)/\(document.pageCount) 页…")
        }
        return pages.joined(separator: "\n\n")
    }

    private func recognizeImage(at url: URL) async throws -> String {
        guard let image = NSImage(contentsOf: url) else { throw DocumentImportError.unreadable }
        return try await recognize(image: image)
    }

    private func recognize(image: NSImage) async throws -> String {
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let cgImage = bitmap.cgImage else {
            throw DocumentImportError.unreadable
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: Self.mergeRecognizedLines(observations))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func mergeRecognizedLines(_ observations: [VNRecognizedTextObservation]) -> String {
        let lines = observations.compactMap { observation -> (String, CGRect)? in
            guard let value = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return (value, observation.boundingBox)
        }.sorted {
            if abs($0.1.midY - $1.1.midY) > max($0.1.height, $1.1.height) * 0.55 { return $0.1.midY > $1.1.midY }
            return $0.1.minX < $1.1.minX
        }
        guard !lines.isEmpty else { return "" }
        let heights = lines.map { $0.1.height }.sorted()
        let typicalHeight = heights[heights.count / 2]
        var result = lines[0].0
        for index in 1..<lines.count {
            let previous = lines[index - 1], current = lines[index]
            let verticalGap = previous.1.minY - current.1.maxY
            let paragraphBreak = verticalGap > typicalHeight * 1.15 || isListStart(current.0)
            if paragraphBreak { result += "\n\n" + current.0; continue }
            if result.last == "-" && usesLatinSpacing(previous.0, current.0) { result.removeLast(); result += current.0 }
            else { result += (usesLatinSpacing(previous.0, current.0) ? " " : "") + current.0 }
        }
        return result
    }

    private static func usesLatinSpacing(_ left: String, _ right: String) -> Bool {
        guard let lhs = left.unicodeScalars.last, let rhs = right.unicodeScalars.first else { return false }
        return lhs.value < 0x2E80 && rhs.value < 0x2E80 && !CharacterSet.whitespacesAndNewlines.contains(lhs)
    }

    private static func isListStart(_ text: String) -> Bool {
        text.range(of: #"^(?:[-•·]|\d+[.)]|[A-Za-z][.)])\s+"#, options: .regularExpression) != nil
    }

    static func normalizeExtractedText(_ text: String) -> String {
        let rawLines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var paragraphs: [String] = []
        var current = ""
        func flush() {
            let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { paragraphs.append(value) }
            current = ""
        }
        for raw in rawLines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { flush(); continue }
            if current.isEmpty { current = line; continue }
            let previousEndsSentence = current.range(of: #"[.!?。！？:：]$"#, options: .regularExpression) != nil
            let blockBoundary = isListStart(line) || (current.count < 70 && previousEndsSentence) || (line.count < 70 && line.range(of: #"[.!?。！？]$"#, options: .regularExpression) == nil)
            if blockBoundary { flush(); current = line }
            else if current.last == "-", usesLatinSpacing(current, line) { current.removeLast(); current += line }
            else { current += usesLatinSpacing(current, line) ? " " + line : line }
        }
        flush()
        return paragraphs.joined(separator: "\n\n")
    }

    static func chunks(from text: String, limit: Int = 3500) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var result: [String] = []
        var current = ""
        for paragraph in paragraphs {
            if current.count + paragraph.count + 2 <= limit {
                current += (current.isEmpty ? "" : "\n\n") + paragraph
            } else {
                if !current.isEmpty { result.append(current) }
                if paragraph.count <= limit { current = paragraph }
                else {
                    var start = paragraph.startIndex
                    while start < paragraph.endIndex {
                        let end = paragraph.index(start, offsetBy: limit, limitedBy: paragraph.endIndex) ?? paragraph.endIndex
                        result.append(String(paragraph[start..<end]))
                        start = end
                    }
                    current = ""
                }
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
