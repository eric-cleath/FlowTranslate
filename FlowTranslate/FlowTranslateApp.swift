import SwiftUI

@main
struct PallasOwlApp: App {
    @State private var state = AppState()

    init() { GlobalCaptureService.shared.start() }

    var body: some Scene {
        Window("PallasOwl", id: "translator") {
            TranslatorView().environment(state).environment(\.locale, state.locale)
        }
        .defaultSize(width: 820, height: 560)

        Window("历史记录", id: "history") {
            HistoryView().environment(state).environment(\.locale, state.locale)
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
        Button("历史记录") { openWindow(id: "history") }
        Divider()
        Button("设置…") { openSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("退出 PallasOwl") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showInput(_ text: String) {
        state.prepareInput(text)
        openWindow(id: "translator")
    }


    private func shortcut(_ action: ShortcutAction) -> String {
        (state.shortcuts[action] ?? .defaultValue(for: action)).display
    }
}
