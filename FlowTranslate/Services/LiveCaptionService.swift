import AppKit
import AVFoundation
import NaturalLanguage
import ScreenCaptureKit
import Speech
import SwiftUI
import UniformTypeIdentifiers

// TCC invokes these authorization callbacks on its own background queue. Keep
// the callback closures outside MainActor isolation so Swift 6 does not trap
// when the system replies off the main thread.
private func requestSpeechRecognitionPermission() async -> Bool {
    await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
            continuation.resume(returning: status == .authorized)
        }
    }
}

private func requestMicrophonePermission() async -> Bool {
    await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { allowed in
            continuation.resume(returning: allowed)
        }
    }
}

@MainActor
@Observable
final class LiveCaptionModel {
    var sourceLanguage = Language.supported.first { $0.code == (UserDefaults.standard.string(forKey: "liveSourceLanguage") ?? "auto") } ?? Language.supported[0]
    var targetLanguage = Language.supported.first { $0.code == (UserDefaults.standard.string(forKey: "liveTargetLanguage") ?? "zh-Hans") } ?? Language.supported[1]
    var audioSource = LiveAudioSource(rawValue: UserDefaults.standard.string(forKey: "liveAudioSource") ?? "") ?? .microphone
    var selectedApplicationBundleID = UserDefaults.standard.string(forKey: "liveApplicationBundleID") ?? ""
    var selectedApplicationName = UserDefaults.standard.string(forKey: "liveApplicationName") ?? ""
    var displayMode = LiveCaptionDisplayMode(rawValue: UserDefaults.standard.string(forKey: "liveDisplayMode") ?? "") ?? .bilingual
    var outputStyle = DocumentOutputStyle(rawValue: UserDefaults.standard.string(forKey: "liveOutputStyle") ?? "") ?? .translated
    var exportFormat = DocumentExportFormat(rawValue: UserDefaults.standard.string(forKey: "liveExportFormat") ?? "") ?? .markdown
    var skipTranslationForTargetLanguage = UserDefaults.standard.object(forKey: "liveSkipTargetLanguage") as? Bool ?? true
    var showsFloatingWindow = UserDefaults.standard.object(forKey: "liveShowsFloatingWindow") as? Bool ?? true
    var captionFontSize = UserDefaults.standard.object(forKey: "liveCaptionFontSize") as? Double ?? 24
    var sourceText = ""
    var translatedText = ""
    var status = "尚未开始"
    var errorMessage: String?
    var isRunning = false
    var detectedLanguageName = ""
    private var hostWindowVisible = false

    private let capture = LiveAudioCapture()
    private var translationTask: Task<Void, Never>?
    var translateHandler: ((String, Language, Language) async throws -> String)?

    func start() async {
        guard !isRunning else { return }
        saveSettings()
        errorMessage = nil
        sourceText = ""
        translatedText = ""
        detectedLanguageName = ""
        status = "正在申请权限…"
        do {
            let recognitionLanguage = sourceLanguage.code == "auto"
                ? (Locale.current.language.languageCode?.identifier ?? "en")
                : sourceLanguage.code
            try await capture.start(source: audioSource, applicationBundleID: selectedApplicationBundleID, languageCode: recognitionLanguage) { [weak self] text, isFinal in
                Task { @MainActor in self?.receive(text, isFinal: isFinal) }
            }
            isRunning = true
            updateHostWindowLevel()
            status = audioSource == .microphone ? "正在聆听麦克风…" : (audioSource == .application ? "正在聆听 \(selectedApplicationName.isEmpty ? "指定应用" : selectedApplicationName)…" : "正在聆听全部应用…")
            if showsFloatingWindow && !hostWindowVisible { LiveCaptionPanelController.shared.show(model: self) }
        } catch {
            errorMessage = error.localizedDescription
            status = "启动失败"
        }
    }

    func stop() {
        translationTask?.cancel()
        capture.stop()
        isRunning = false
        status = sourceText.isEmpty ? "已停止" : "转写已停止"
        updateHostWindowLevel()
        LiveCaptionPanelController.shared.hide()
    }

    func clear() {
        sourceText = ""
        translatedText = ""
        detectedLanguageName = ""
        errorMessage = nil
    }

    func setHostWindowVisible(_ visible: Bool) {
        hostWindowVisible = visible
        updateHostWindowLevel()
        guard isRunning, showsFloatingWindow else {
            if visible { LiveCaptionPanelController.shared.hide() }
            return
        }
        if visible { LiveCaptionPanelController.shared.hide() }
        else { LiveCaptionPanelController.shared.show(model: self) }
    }

    func saveSettings() {
        UserDefaults.standard.set(sourceLanguage.code, forKey: "liveSourceLanguage")
        UserDefaults.standard.set(targetLanguage.code, forKey: "liveTargetLanguage")
        UserDefaults.standard.set(audioSource.rawValue, forKey: "liveAudioSource")
        UserDefaults.standard.set(selectedApplicationBundleID, forKey: "liveApplicationBundleID")
        UserDefaults.standard.set(selectedApplicationName, forKey: "liveApplicationName")
        UserDefaults.standard.set(displayMode.rawValue, forKey: "liveDisplayMode")
        UserDefaults.standard.set(outputStyle.rawValue, forKey: "liveOutputStyle")
        UserDefaults.standard.set(exportFormat.rawValue, forKey: "liveExportFormat")
        UserDefaults.standard.set(skipTranslationForTargetLanguage, forKey: "liveSkipTargetLanguage")
        UserDefaults.standard.set(showsFloatingWindow, forKey: "liveShowsFloatingWindow")
        UserDefaults.standard.set(captionFontSize, forKey: "liveCaptionFontSize")
    }

    func export() {
        let text = exportText()
        guard !text.isEmpty else { return }
        saveSettings()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportFormat == .markdown ? .init(filenameExtension: "md")! : .plainText]
        panel.nameFieldStringValue = "PallasOwl-实时字幕-\(fileDate()).\(exportFormat.fileExtension)"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                status = "字幕记录已导出"
            } catch {
                errorMessage = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    private func exportText() -> String {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if outputStyle == .translated {
            guard !translation.isEmpty else { return "" }
            if exportFormat == .plainText { return translation }
            return markdownFrontmatter() + "# 实时字幕译文\n\n\(translation)\n"
        }
        guard !source.isEmpty || !translation.isEmpty else { return "" }
        if exportFormat == .plainText {
            return "原文\n\(source)\n\n译文\n\(translation)"
        }
        return markdownFrontmatter() + """
        # 实时字幕记录

        <table style="width:100%; table-layout:fixed;">
        <colgroup><col style="width:50%;"><col style="width:50%;"></colgroup>
        <thead><tr><th>原文</th><th>译文</th></tr></thead>
        <tbody><tr><td>\(htmlCell(source))</td><td>\(htmlCell(translation))</td></tr></tbody>
        </table>

        """
    }

    private func markdownFrontmatter() -> String {
        """
        ---
        title: "PallasOwl 实时字幕"
        created_at: "\(ISO8601DateFormatter().string(from: Date()))"
        source_language: "\(sourceLanguage.name)"
        target_language: "\(targetLanguage.name)"
        output_style: "\(outputStyle.rawValue)"
        tags:
          - PallasOwl
          - 实时字幕
        ---

        """
    }

    private func htmlCell(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private func fileDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private func updateHostWindowLevel() {
        let window = NSApp.windows.first { $0.title == "PallasOwl Translator" }
        window?.level = isRunning && hostWindowVisible ? .floating : .normal
    }

    private func receive(_ text: String, isFinal: Bool) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        sourceText = cleaned
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(isFinal ? 120 : 650))
            guard !Task.isCancelled, let self else { return }
            await self.translateCurrent(cleaned)
        }
    }

    private func translateCurrent(_ text: String) async {
        let detected = detectedLanguage(for: text)
        detectedLanguageName = detected?.name ?? "识别中"
        if skipTranslationForTargetLanguage, sameBaseLanguage(detected?.code, targetLanguage.code) {
            translatedText = ""
            status = "检测到目标语言，仅记录原文"
            return
        }
        guard let translateHandler else {
            errorMessage = "实时字幕尚未配置翻译引擎。"
            return
        }
        status = "正在翻译…"
        do {
            let source = detected ?? sourceLanguage
            translatedText = try await translateHandler(text, source, targetLanguage)
            status = isRunning ? "实时字幕运行中" : "翻译完成"
        } catch {
            errorMessage = error.localizedDescription
            status = "翻译失败，转写仍在继续"
        }
    }

    private func detectedLanguage(for text: String) -> Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let code = recognizer.dominantLanguage?.rawValue else { return sourceLanguage.code == "auto" ? nil : sourceLanguage }
        return Language.supported.first { sameBaseLanguage($0.code, code) }
    }

    private func sameBaseLanguage(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs else { return false }
        let a = lhs.lowercased().split(separator: "-").first.map(String.init)
        let b = rhs.lowercased().split(separator: "-").first.map(String.init)
        return a == b
    }
}

private final class LiveAudioCapture: NSObject, @unchecked Sendable, SCStreamOutput {
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var stream: SCStream?

    @MainActor
    func start(source: LiveAudioSource, applicationBundleID: String, languageCode: String, update: @escaping (String, Bool) -> Void) async throws {
        let authorized = await requestSpeechRecognitionPermission()
        guard authorized else { throw LiveCaptionError.speechPermission }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode)), recognizer.isAvailable else {
            throw LiveCaptionError.recognizerUnavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result { update(result.bestTranscription.formattedString, result.isFinal) }
            if error != nil { /* A stopped stream commonly finishes with a cancellation error. */ }
        }
        if source == .microphone { try await startMicrophone(request: request) }
        else { try await startSystemAudio(applicationBundleID: source == .application ? applicationBundleID : nil) }
    }

    @MainActor
    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        if let stream { Task { try? await stream.stopCapture() } }
        stream = nil
        request = nil
        task = nil
    }

    @MainActor
    private func startMicrophone(request: SFSpeechAudioBufferRecognitionRequest) async throws {
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        if permission == .denied || permission == .restricted { throw LiveCaptionError.microphonePermission }
        if permission == .notDetermined {
            let allowed = await requestMicrophonePermission()
            guard allowed else { throw LiveCaptionError.microphonePermission }
        }
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        audioEngine.prepare()
        try audioEngine.start()
    }

    @MainActor
    private func startSystemAudio(applicationBundleID: String?) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw LiveCaptionError.noDisplay }
        let filter: SCContentFilter
        if let applicationBundleID, !applicationBundleID.isEmpty,
           let selected = content.applications.first(where: { $0.bundleIdentifier == applicationBundleID }) {
            filter = SCContentFilter(display: display, including: [selected], exceptingWindows: [])
        } else {
            let ownApp = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: ownApp.map { [$0] } ?? [], exceptingWindows: [])
        }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.pallasowl.live-audio"))
        self.stream = stream
        try await stream.startCapture()
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        request?.appendAudioSampleBuffer(sampleBuffer)
    }
}

private enum LiveCaptionError: LocalizedError {
    case speechPermission, microphonePermission, recognizerUnavailable, noDisplay
    var errorDescription: String? {
        switch self {
        case .speechPermission: "尚未获得语音识别权限，请在系统设置的隐私与安全性中允许 PallasOwl Translator。"
        case .microphonePermission: "尚未获得麦克风权限，请在系统设置的隐私与安全性中允许 PallasOwl Translator。"
        case .recognizerUnavailable: "当前语言的系统语音识别暂时不可用。"
        case .noDisplay: "没有找到可捕获系统音频的显示器。"
        }
    }
}

@MainActor
final class LiveCaptionPanelController {
    static let shared = LiveCaptionPanelController()
    private var panel: NSPanel?

    func show(model: LiveCaptionModel) {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(rootView: LiveCaptionOverlay(model: model))
            self.panel = panel
        } else {
            panel?.contentView = NSHostingView(rootView: LiveCaptionOverlay(model: model))
        }
        if let screen = NSScreen.main {
            let frame = panel!.frame
            panel?.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - frame.width / 2, y: screen.visibleFrame.minY + 55))
        }
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }
}

private struct LiveCaptionOverlay: View {
    @Bindable var model: LiveCaptionModel
    var body: some View {
        VStack(spacing: 7) {
            if model.displayMode != .translationOnly, !model.sourceText.isEmpty {
                Text(model.sourceText).foregroundStyle(.white.opacity(0.82))
            }
            if model.displayMode != .sourceOnly, !model.translatedText.isEmpty {
                Text(model.translatedText).foregroundStyle(.white).fontWeight(.semibold)
            }
        }
        .font(.system(size: model.captionFontSize))
        .multilineTextAlignment(.center).lineLimit(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 15))
    }
}
