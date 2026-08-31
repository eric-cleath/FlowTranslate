import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Vision

@MainActor
final class GlobalCaptureService {
    static let shared = GlobalCaptureService()
    var onInput: (() -> Void)?
    var onSelection: ((String) -> Void)?
    var onScreenshot: ((String) -> Void)?
    var onCrossLanguageWriting: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private var refs: [EventHotKeyRef?] = []
    private var progressPanel: NSPanel?
    private init() {}

    func start() {
        guard refs.isEmpty else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            Task { @MainActor in GlobalCaptureService.shared.handle(id.id) }
            return noErr
        }, 1, &eventType, nil, nil)
        reloadShortcuts(loadSavedShortcuts())
    }

    func reloadShortcuts(_ shortcuts: [ShortcutAction: ShortcutConfig]) {
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        refs.removeAll()
        let actions: [(ShortcutAction, UInt32)] = [(.input, 1), (.selection, 2), (.screenshot, 3), (.crossWriting, 4)]
        for (action, id) in actions {
            let config = shortcuts[action] ?? .defaultValue(for: action)
            register(id: id, key: keyCode(for: config.letter), modifiers: carbonModifiers(for: config))
        }
    }

    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func captureSelection() {
        captureSelectedText(restoreClipboard: true, completion: { self.onSelection?($0) })
    }

    func captureForCrossLanguageWriting() {
        captureSelectedText(restoreClipboard: false, completion: { self.onCrossLanguageWriting?($0) })
    }

    func replaceSelection(with text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let previous else { return }
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }
    }

    func beginCrossWritingProgress() {
        endCrossWritingProgress()
        let indicator = NSProgressIndicator(frame: NSRect(x: 14, y: 12, width: 242, height: 8))
        indicator.style = .bar
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        let label = NSTextField(labelWithString: "PallasOwl 正在处理…")
        label.frame = NSRect(x: 14, y: 29, width: 242, height: 20)
        let panel = NSPanel(
            contentRect: NSRect(x: NSEvent.mouseLocation.x + 14, y: NSEvent.mouseLocation.y - 66, width: 270, height: 58),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.contentView?.addSubview(indicator)
        panel.contentView?.addSubview(label)
        panel.orderFrontRegardless()
        progressPanel = panel
    }

    func endCrossWritingProgress() {
        progressPanel?.orderOut(nil)
        progressPanel = nil
    }

    private func captureSelectedText(restoreClipboard: Bool, completion: @escaping (String) -> Void) {
        let pasteboard = NSPasteboard.general
        let old = pasteboard.string(forType: .string)
        let oldChange = pasteboard.changeCount
        postCommandC()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard pasteboard.changeCount != oldChange, let text = pasteboard.string(forType: .string), !text.isEmpty else {
                self.onError?("没有读取到选中文字。请确认已选中文字；如仍失败，请在“隐私与安全性 → 辅助功能”中重新添加 PallasOwl。")
                return
            }
            completion(text)
            if restoreClipboard, let old { pasteboard.clearContents(); pasteboard.setString(old, forType: .string) }
        }
    }

    func captureScreenshot() {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            onError?("需要屏幕录制权限。授权后请重启 PallasOwl，再按截图翻译快捷键。")
            return
        }
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "PallasOwl-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", fileURL.path]
        process.terminationHandler = { _ in
            defer { try? FileManager.default.removeItem(at: fileURL) }
            guard let image = NSImage(contentsOf: fileURL), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let cgImage = bitmap.cgImage else { return }
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = Self.mergeRecognizedLines(observations)
                Task { @MainActor in
                    if text.isEmpty { self.onError?("截图中没有识别到文字。") }
                    else { self.onScreenshot?(text) }
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "ja-JP", "ko-KR", "en-US"]
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        }
        do { try process.run() }
        catch { onError?("无法启动系统截图：\(error.localizedDescription)") }
    }

    private func register(id: UInt32, key: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x46544C57), id: id)
        RegisterEventHotKey(key, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }

    private nonisolated static func mergeRecognizedLines(_ observations: [VNRecognizedTextObservation]) -> String {
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
            let previous = lines[index - 1]
            let current = lines[index]
            let verticalGap = previous.1.minY - current.1.maxY
            let paragraphBreak = verticalGap > typicalHeight * 1.15 || isListStart(current.0)
            if paragraphBreak { result += "\n\n" + current.0; continue }
            if result.last == "-" && usesLatinSpacing(previous.0, current.0) {
                result.removeLast(); result += current.0
            } else {
                result += (usesLatinSpacing(previous.0, current.0) ? " " : "") + current.0
            }
        }
        return result
    }

    private nonisolated static func usesLatinSpacing(_ left: String, _ right: String) -> Bool {
        guard let lhs = left.unicodeScalars.last, let rhs = right.unicodeScalars.first else { return false }
        return lhs.value < 0x2E80 && rhs.value < 0x2E80 && !CharacterSet.whitespacesAndNewlines.contains(lhs)
    }

    private nonisolated static func isListStart(_ text: String) -> Bool {
        text.range(of: #"^(?:[-•·]|\d+[.)]|[A-Za-z][.)])\s+"#, options: .regularExpression) != nil
    }

    private func carbonModifiers(for config: ShortcutConfig) -> UInt32 {
        var value: UInt32 = 0
        if config.control { value |= UInt32(controlKey) }
        if config.option { value |= UInt32(optionKey) }
        if config.shift { value |= UInt32(shiftKey) }
        if config.command { value |= UInt32(cmdKey) }
        return value
    }

    private func keyCode(for letter: String) -> UInt32 {
        let values: [String: UInt32] = [
            "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C), "D": UInt32(kVK_ANSI_D),
            "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F), "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H),
            "I": UInt32(kVK_ANSI_I), "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
            "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O), "P": UInt32(kVK_ANSI_P),
            "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R), "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T),
            "U": UInt32(kVK_ANSI_U), "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
            "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z)
        ]
        return values[letter.uppercased()] ?? UInt32(kVK_ANSI_A)
    }

    private func loadSavedShortcuts() -> [ShortcutAction: ShortcutConfig] {
        guard let text = UserDefaults.standard.string(forKey: "shortcuts"), let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode([ShortcutAction: ShortcutConfig].self, from: data) else {
            return Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, .defaultValue(for: $0)) })
        }
        return value
    }

    private func handle(_ id: UInt32) {
        if id == 1 { onInput?() }
        if id == 2 { captureSelection() }
        if id == 3 { captureScreenshot() }
        if id == 4 { captureForCrossLanguageWriting() }
    }

    private func postCommandC() {
        postKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags; up?.flags = flags
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }
}
