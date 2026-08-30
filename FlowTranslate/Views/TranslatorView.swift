import SwiftUI

struct TranslatorView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var showsDocumentMode = false

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            Picker("模式", selection: Binding(get: { showsDocumentMode ? "__document" : state.mode.rawValue }, set: { value in
                if value == "__document" { if !showsDocumentMode { state.clearWorkspace() }; showsDocumentMode = true }
                else if let mode = WorkMode(rawValue: value) { showsDocumentMode = false; state.switchMode(to: mode) }
            })) {
                ForEach(WorkMode.allCases.filter { $0 != .summarize }) { mode in
                    Label(LocalizedStringKey(mode.rawValue), systemImage: mode.systemIcon).tag(mode.rawValue)
                }
                Label("文档", systemImage: "doc.text").tag("__document")
            }
            .pickerStyle(.segmented)
            .padding()

            if showsDocumentMode {
                DocumentTranslationView(embedded: true)
            } else {

            HStack {
                if state.mode == .crossLanguageWriting {
                    Text("简体中文").frame(maxWidth: .infinity)
                } else {
                    languagePicker("源语言", selection: $state.sourceLanguage, allowsAuto: true)
                }
                Button(action: state.swapLanguages) {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.plain)
                .disabled(state.mode == .crossLanguageWriting || state.sourceLanguage.code == "auto")
                languagePicker(
                    "目标语言",
                    selection: state.mode == .crossLanguageWriting ? $state.crossWritingTargetLanguage : $state.targetLanguage,
                    allowsAuto: false
                )
            }
            .padding(.horizontal)

            HSplitView {
                editor(title: "原文", text: $state.input, placeholder: "输入或粘贴文字…", language: state.mode == .crossLanguageWriting ? Language.supported[1] : state.sourceLanguage)
                editor(title: "结果", text: $state.output, placeholder: "处理结果会显示在这里", language: state.mode == .crossLanguageWriting ? state.crossWritingTargetLanguage : state.targetLanguage, isOutput: true)
            }
            .padding()

            if state.mode == .translate, !state.translationSummary.isEmpty || state.isSummarizing || state.summaryError != nil {
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Label("译文总结", systemImage: "text.alignleft").font(.headline); Spacer(); if state.isSummarizing { ProgressView().controlSize(.small) } }
                    if let error = state.summaryError { Text(error).font(.callout).foregroundStyle(.red) }
                    else if !state.translationSummary.isEmpty { Text(state.translationSummary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
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
                Button { openSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("打开设置")
                Text("⌘↩︎ 开始")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if state.mode == .translate {
                    Text("· 当前服务：\(state.translationProvider.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("清空") {
                    state.clearWorkspace()
                }
                Button("复制结果", action: state.copyOutput)
                    .disabled(state.output.isEmpty)
                Button {
                    Task { await state.run() }
                } label: {
                    if state.isWorking { ProgressView().controlSize(.small) } else { Text(LocalizedStringKey(state.mode.rawValue)) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isWorking)
            }
            .padding()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { bindGlobalShortcuts() }
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
        capture.onScreenshot = { showTranslator(text: $0, autoTranslate: true) }
        capture.onCrossLanguageWriting = { text in
            showsDocumentMode = false
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
        capture.onError = {
            state.prepareInput("", activate: false)
            state.errorMessage = $0
            showTranslator(text: nil, autoTranslate: false)
        }
    }

    private func showTranslator(text: String?, autoTranslate: Bool) {
        showsDocumentMode = false
        if let text { state.prepareInput(text) }
        openWindow(id: "translator")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.windows.first(where: { $0.title == "PallasOwl" })?.makeKeyAndOrderFront(nil)
        }
        if autoTranslate {
            Task { await state.run() }
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
            }.font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 300)
    }
}
