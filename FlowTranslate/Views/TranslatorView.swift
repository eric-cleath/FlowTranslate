import SwiftUI

struct TranslatorView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var showsDocumentMode = false
    @State private var showsLiveCaptionMode = false
    @State private var showsMediaMode = false
    @State private var showsChannelTrackingMode = false

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            ModeNavigationBar(selection: Binding(get: { showsChannelTrackingMode ? "__tracking" : (showsMediaMode ? "__media" : (showsLiveCaptionMode ? "__live" : (showsDocumentMode ? "__document" : state.mode.rawValue))) }, set: { value in
                if value == "__document" { if !showsDocumentMode { state.clearWorkspace() }; showsLiveCaptionMode = false; showsMediaMode = false; showsChannelTrackingMode = false; showsDocumentMode = true }
                else if value == "__live" { state.clearWorkspace(); showsDocumentMode = false; showsMediaMode = false; showsChannelTrackingMode = false; showsLiveCaptionMode = true }
                else if value == "__media" { state.clearWorkspace(); showsDocumentMode = false; showsLiveCaptionMode = false; showsChannelTrackingMode = false; showsMediaMode = true }
                else if value == "__tracking" { state.clearWorkspace(); showsDocumentMode = false; showsLiveCaptionMode = false; showsMediaMode = false; showsChannelTrackingMode = true }
                else if let mode = WorkMode(rawValue: value) { showsDocumentMode = false; showsLiveCaptionMode = false; showsMediaMode = false; showsChannelTrackingMode = false; state.switchMode(to: mode) }
            }))
            .padding(.horizontal).padding(.vertical, 12)

            if showsChannelTrackingMode {
                ChannelTrackingPlaceholderView()
            } else if showsLiveCaptionMode {
                LiveCaptionView()
            } else if showsMediaMode {
                MediaProcessingView()
            } else if showsDocumentMode {
                DocumentTranslationView(embedded: true)
            } else {

            HStack {
                if state.mode == .polish {
                    Label("保持原文语言", systemImage: "character.cursor.ibeam")
                        .frame(maxWidth: .infinity)
                } else if state.mode == .crossLanguageWriting {
                    languagePicker("源语言", selection: $state.crossWritingSourceLanguage, allowsAuto: false)
                } else {
                    languagePicker("源语言", selection: $state.sourceLanguage, allowsAuto: true)
                }
                if state.mode != .polish {
                    Button {
                        if state.mode == .crossLanguageWriting {
                            let source = state.crossWritingSourceLanguage
                            state.crossWritingSourceLanguage = state.crossWritingTargetLanguage
                            state.crossWritingTargetLanguage = source
                            try? state.saveSettings()
                        } else { state.swapLanguages() }
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.plain)
                    .disabled(state.mode != .crossLanguageWriting && state.sourceLanguage.code == "auto")
                    languagePicker(
                        "目标语言",
                        selection: state.mode == .crossLanguageWriting ? $state.crossWritingTargetLanguage : $state.targetLanguage,
                        allowsAuto: false
                    )
                }
            }
            .padding(.horizontal)

            HSplitView {
                editor(title: "原文", text: $state.input, placeholder: "输入或粘贴文字…", language: state.mode == .crossLanguageWriting ? state.crossWritingSourceLanguage : state.sourceLanguage)
                editor(title: "结果", text: $state.output, placeholder: "处理结果会显示在这里", language: state.mode == .crossLanguageWriting ? state.crossWritingTargetLanguage : state.targetLanguage, isOutput: true)
            }
            .padding()

            if state.mode == .translate, !state.translationSummary.isEmpty || state.isSummarizing || state.summaryError != nil {
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Label("译文总结", systemImage: "text.alignleft").font(.headline); Spacer(); if state.isSummarizing { ProgressView().controlSize(.small) } }
                    if let error = state.summaryError { Text(error).font(.callout).foregroundStyle(.red) }
                    else if !state.translationSummary.isEmpty { Text(state.translationSummary).font(.system(size: state.editorFontSize)).lineSpacing(state.editorLineSpacing).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }.padding(12).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal)
            }

            if let error = state.errorMessage {
                Text(error).foregroundStyle(.red).font(.callout).padding(.horizontal)
            } else if state.isWorking {
                VStack(spacing: 7) {
                    if state.mode == .crossLanguageWriting { ProgressView().progressViewStyle(.linear).frame(maxWidth: 360) }
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(state.processingStatus).font(.callout).foregroundStyle(.secondary) }
                }.padding(.horizontal)
            }

            HStack {
                Button { openSettings(); bringPallasOwlSettingsWindowToFront() } label: { Image(systemName: "gearshape").font(.system(size: 16, weight: .semibold)) }
                    .buttonStyle(.plain).help("打开设置")
                Text("↩︎ 翻译")
                    .foregroundStyle(.secondary)
                if state.mode == .translate {
                    Text("· 当前服务：\(state.translationProvider.rawValue)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.callout)
            .padding()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            bindGlobalShortcuts()
            applyRequestedMainMode()
        }
        .onChange(of: state.requestedMainMode) { _, _ in applyRequestedMainMode() }
        .onChange(of: state.input) { _, value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.output = ""; state.translationSummary = ""; state.errorMessage = nil; state.summaryError = nil
            }
        }
        .onChange(of: state.crossWritingSourceLanguage) { _, _ in try? state.saveSettings() }
        .onChange(of: state.crossWritingTargetLanguage) { _, _ in try? state.saveSettings() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            state.reloadSecretsAfterUnlock()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)) { _ in
            state.reloadSecretsAfterUnlock()
        }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.shift) { return .ignored }
            guard !state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !state.isWorking else { return .ignored }
            Task { await state.run() }
            return .handled
        }
    }

    private func bindGlobalShortcuts() {
        let capture = GlobalCaptureService.shared
        capture.onInput = { showTranslator(text: "", autoTranslate: false) }
        capture.onSelection = { showTranslator(text: $0, autoTranslate: true) }
        capture.onScreenshot = { text, diagnosticID in
            showTranslator(text: text, autoTranslate: true, diagnosticID: diagnosticID)
        }
        capture.onCrossLanguageWriting = { text in
            showsDocumentMode = false
            showsMediaMode = false
            showsChannelTrackingMode = false
            state.prepareInput(text, mode: .crossLanguageWriting, activate: false)
            capture.beginCrossWritingProgress()
            Task {
                await state.run()
                capture.endCrossWritingProgress()
                if state.errorMessage == nil, !state.output.isEmpty {
                    capture.replaceSelection(with: state.output)
                } else {
                    showTranslator(text: nil, autoTranslate: false)
                }
            }
        }
        capture.onOpenLiveCaption = { showLiveCaption(start: false) }
        capture.onToggleLiveCaption = { showLiveCaption(start: true) }
        capture.onInstantSelection = { text, completion in
            Task {
                do { completion(.success(try await state.translateInstantSelection(text))) }
                catch { completion(.failure(error)) }
            }
        }
        capture.onInstantLanguageDirection = { (state.sourceLanguage.name, state.targetLanguage.name) }
        capture.onOpenInstantSelectionMain = { showTranslator(text: $0, autoTranslate: true) }
        capture.onSpeakInstantSelection = { state.speak($0, language: state.targetLanguage) }
        capture.onError = {
            state.isWorking = false
            state.processingStatus = ""
            state.prepareInput("", activate: false)
            state.errorMessage = $0
            showTranslator(text: nil, autoTranslate: false)
        }
    }

    private func showLiveCaption(start: Bool) {
        showsDocumentMode = false
        showsMediaMode = false
        showsChannelTrackingMode = false
        showsLiveCaptionMode = true
        openWindow(id: "translator")
        bringTranslatorWindowToFront()
        if start {
            if state.liveCaption.isRunning { state.liveCaption.stop() }
            else {
                state.liveCaption.translateHandler = { text, source, target in
                    try await state.translateLiveCaption(text, source: source, target: target)
                }
                Task { await state.liveCaption.start() }
            }
        }
    }

    private func applyRequestedMainMode() {
        guard let requested = state.requestedMainMode else { return }
        state.requestedMainMode = nil
        if requested == "__live" {
            showsDocumentMode = false
            showsMediaMode = false
            showsChannelTrackingMode = false
            showsLiveCaptionMode = true
        }
    }

    private func bringTranslatorWindowToFront(attempt: Int = 0, diagnosticID: UUID? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let retryDelays: [TimeInterval] = [0.02, 0.08, 0.15, 0.25, 0.4, 0.6]
        let delay = retryDelays[min(attempt, retryDelays.count - 1)]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let window = translatorWindow() {
                if let diagnosticID {
                    DiagnosticLogger.shared.record(session: diagnosticID, event: "window.found", details: [
                        "attempt": "\(attempt + 1)",
                        "miniaturized": "\(window.isMiniaturized)",
                        "visible": "\(window.isVisible)"
                    ])
                }
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.orderFrontRegardless()
                window.makeKey()
            } else if attempt + 1 < retryDelays.count {
                if let diagnosticID { DiagnosticLogger.shared.record(session: diagnosticID, event: "window.retry", details: ["attempt": "\(attempt + 1)"]) }
                bringTranslatorWindowToFront(attempt: attempt + 1, diagnosticID: diagnosticID)
            } else if let diagnosticID {
                DiagnosticLogger.shared.record(session: diagnosticID, event: "window.not-found", details: ["attempts": "\(retryDelays.count)"])
            }
        }
    }

    private func showTranslator(text: String?, autoTranslate: Bool, diagnosticID: UUID? = nil) {
        showsDocumentMode = false
        showsLiveCaptionMode = false
        showsMediaMode = false
        showsChannelTrackingMode = false
        if let text {
            state.prepareInput(text)
            if let diagnosticID { DiagnosticLogger.shared.record(session: diagnosticID, event: "ui.input.prepared", details: ["characters": "\(text.count)"]) }
        }
        openWindow(id: "translator")
        if let diagnosticID { DiagnosticLogger.shared.record(session: diagnosticID, event: "window.open.requested") }
        bringTranslatorWindowToFront(diagnosticID: diagnosticID)
        if autoTranslate {
            Task {
                let translationStartedAt = Date()
                if let diagnosticID { DiagnosticLogger.shared.record(session: diagnosticID, event: "translation.started") }
                await state.run()
                if let diagnosticID {
                    DiagnosticLogger.shared.record(session: diagnosticID, event: "translation.completed", details: [
                        "elapsed_ms": "\(Int((Date().timeIntervalSince(translationStartedAt) * 1_000).rounded()))",
                        "result": state.errorMessage == nil && !state.output.isEmpty ? "success" : "failure"
                    ])
                }
            }
        }
    }

    private func translatorWindow() -> NSWindow? {
        let settingsWords = ["settings", "设置", "réglages", "設定"]
        return NSApp.windows.first { window in
            window.title.localizedCaseInsensitiveContains("PallasOwl Translator") &&
            !settingsWords.contains { window.title.localizedCaseInsensitiveContains($0) }
        }
    }

    private func languagePicker(_ title: String, selection: Binding<Language>, allowsAuto: Bool) -> some View {
        Picker(title, selection: selection) {
            ForEach(Language.supported.filter { allowsAuto || $0.code != "auto" }) { language in
                Text(LocalizedStringKey(language.name)).tag(language)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    private func editor(title: String, text: Binding<String>, placeholder: String, language: Language, isOutput: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.system(size: state.editorFontSize))
                    .lineSpacing(state.editorLineSpacing)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                if text.wrappedValue.isEmpty {
                    Text(placeholder).foregroundStyle(.tertiary).padding(14).allowsHitTesting(false)
                }
            }
            HStack(spacing: 14) {
                Button {
                    if state.isSpeaking { state.stopSpeaking() } else { state.speak(text.wrappedValue, language: language) }
                } label: { Label(state.isSpeaking ? "停止" : "朗读", systemImage: state.isSpeaking ? "stop.fill" : "speaker.wave.2") }
                    .buttonStyle(.plain).disabled(text.wrappedValue.isEmpty)
                Button { state.copyText(text.wrappedValue) } label: { Label("复制", systemImage: "doc.on.doc") }
                    .buttonStyle(.plain).disabled(text.wrappedValue.isEmpty)
                if isOutput && state.mode == .translate {
                    Button { Task { await state.summarizeTranslation() } } label: { Label("总结译文", systemImage: "text.alignleft") }
                        .buttonStyle(.plain).disabled(text.wrappedValue.isEmpty || state.isWorking || state.isSummarizing)
                }
                Spacer()
            }.font(.callout).foregroundStyle(.secondary)
        }
        .frame(minWidth: 300)
    }
}

private struct ModeNavigationItem: Identifiable {
    let id: String
    let title: String
    let icon: String
}

private struct ModeNavigationBar: View {
    @Binding var selection: String
    @State private var hoveredID: String?
    @Namespace private var selectedBackground

    private let items: [ModeNavigationItem] = [
        .init(id: WorkMode.translate.rawValue, title: WorkMode.translate.rawValue, icon: WorkMode.translate.systemIcon),
        .init(id: WorkMode.polish.rawValue, title: WorkMode.polish.rawValue, icon: WorkMode.polish.systemIcon),
        .init(id: WorkMode.crossLanguageWriting.rawValue, title: WorkMode.crossLanguageWriting.rawValue, icon: WorkMode.crossLanguageWriting.systemIcon),
        .init(id: "__document", title: "文档", icon: "doc.text"),
        .init(id: "__live", title: "实时字幕", icon: "captions.bubble"),
        .init(id: "__media", title: "媒体", icon: "film.stack"),
        .init(id: "__tracking", title: "频道追踪", icon: "dot.radiowaves.left.and.right")
    ]

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(items) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.24)) { selection = item.id }
                    } label: {
                        Label {
                            Text(LocalizedStringKey(item.title))
                        } icon: {
                            Image(systemName: item.icon)
                        }
                        .font(.system(size: 12.5, weight: selection == item.id ? .semibold : .medium))
                        .foregroundStyle(selection == item.id ? Color.white : Color.primary.opacity(0.78))
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .frame(minWidth: ["__live", "__tracking"].contains(item.id) ? 92 : 74)
                        .background {
                            if selection == item.id {
                                Capsule(style: .continuous)
                                    .fill(LinearGradient(
                                        colors: [Color(red: 0.05, green: 0.69, blue: 0.98), Color(red: 0.48, green: 0.30, blue: 1.0)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                                    .matchedGeometryEffect(id: "selectedMode", in: selectedBackground)
                                    .shadow(color: Color.blue.opacity(0.22), radius: 5, y: 2)
                            } else if hoveredID == item.id {
                                Capsule(style: .continuous).fill(Color.primary.opacity(0.075))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.12)) { hoveredID = hovering ? item.id : nil }
                    }
                    .help(item.title)
                }
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Color.primary.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.07), radius: 7, y: 2)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
