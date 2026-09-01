import AppKit
import SwiftUI

@main
struct PallasOwlApp: App {
    @State private var state = AppState()

    init() { GlobalCaptureService.shared.start() }

    var body: some Scene {
        Window("PallasOwl Translator", id: "translator") {
            TranslatorView().environment(state).environment(\.locale, state.locale)
        }
        .defaultSize(width: 820, height: 560)

        Window("历史记录", id: "history") {
            HistoryView().environment(state).environment(\.locale, state.locale)
        }

        Window("文档翻译", id: "document-translation") {
            DocumentTranslationView().environment(state).environment(\.locale, state.locale)
        }

        Settings {
            SettingsView().environment(state).environment(\.locale, state.locale)
        }

        MenuBarExtra {
            MenuBarContent().environment(state).environment(\.locale, state.locale)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(AppState.self) private var state

    var body: some View {
        Button("打开翻译窗口") { showInput("") }
        Button("输入翻译  \(shortcut(.input))") { showInput("") }
        Button("划词翻译  \(shortcut(.selection))") { GlobalCaptureService.shared.captureSelection() }
        Button("截图翻译  \(shortcut(.screenshot))") { GlobalCaptureService.shared.captureScreenshot() }
        Button("跨语写作并替换  \(shortcut(.crossWriting))") { GlobalCaptureService.shared.captureForCrossLanguageWriting() }
        Menu("实时字幕音频源") {
            audioSourceButton(.microphone)
            audioSourceButton(.allApplications)
            Divider()
            ForEach(runningApplications, id: \.bundleIdentifier) { app in
                Button {
                    state.liveCaption.audioSource = .application
                    state.liveCaption.selectedApplicationBundleID = app.bundleIdentifier ?? ""
                    state.liveCaption.selectedApplicationName = app.localizedName ?? ""
                    state.liveCaption.saveSettings()
                } label: {
                    if state.liveCaption.audioSource == .application && state.liveCaption.selectedApplicationBundleID == app.bundleIdentifier {
                        Label(app.localizedName ?? "应用", systemImage: "checkmark")
                    } else { Text(app.localizedName ?? "应用") }
                }
            }
        }
        Button("文档翻译…") { openWindow(id: "document-translation") }
        Button("打开实时字幕  \(shortcut(.openLiveCaption))") { showLiveCaptions() }
        Button("开始/停止实时字幕  \(shortcut(.toggleLiveCaption))") { toggleLiveCaptions() }
        Button("历史记录") { openWindow(id: "history") }
        Divider()
        Button("设置…") { showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("退出 PallasOwl Translator") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showInput(_ text: String) {
        state.prepareInput(text)
        openWindow(id: "translator")
        bringWindowToFront(title: "PallasOwl Translator")
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        bringWindowToFront(title: "PallasOwl Translator 设置")
    }

    private func bringWindowToFront(title: String) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.windows.first(where: { $0.title == title || $0.title.contains(title) })?.makeKeyAndOrderFront(nil)
        }
    }

    private func showLiveCaptions() {
        state.requestedMainMode = "__live"
        openWindow(id: "translator")
        bringWindowToFront(title: "PallasOwl Translator")
    }

    private func toggleLiveCaptions() {
        showLiveCaptions()
        if state.liveCaption.isRunning { state.liveCaption.stop(); return }
        state.liveCaption.translateHandler = { text, source, target in
            try await state.translateLiveCaption(text, source: source, target: target)
        }
        Task { await state.liveCaption.start() }
    }

    @ViewBuilder private func audioSourceButton(_ source: LiveAudioSource) -> some View {
        Button {
            state.liveCaption.audioSource = source
            state.liveCaption.saveSettings()
        } label: {
            if state.liveCaption.audioSource == source { Label(source.rawValue, systemImage: "checkmark") }
            else { Text(source.rawValue) }
        }
    }

    private var runningApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }


    private func shortcut(_ action: ShortcutAction) -> String {
        (state.shortcuts[action] ?? .defaultValue(for: action)).display
    }
}
