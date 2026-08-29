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
            if !value.isEmpty { pages.append(value) }
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
                let lines = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines.joined(separator: "\n"))
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
