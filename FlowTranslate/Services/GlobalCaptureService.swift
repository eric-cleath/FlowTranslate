import AppKit
@preconcurrency import ApplicationServices
import Carbon
import SwiftUI
import Vision

@MainActor
final class GlobalCaptureService {
    static let shared = GlobalCaptureService()
    var onInput: (() -> Void)?
    var onSelection: ((String) -> Void)?
    var onScreenshot: ((String) -> Void)?
    var onCrossLanguageWriting: ((String) -> Void)?
    var onOpenLiveCaption: (() -> Void)?
    var onToggleLiveCaption: (() -> Void)?
    var onInstantSelection: ((String, @escaping (Result<String, Error>) -> Void) -> Void)?
    var onInstantLanguageDirection: (() -> (source: String, target: String))?
    var onOpenInstantSelectionMain: ((String) -> Void)?
    var onSpeakInstantSelection: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private var refs: [EventHotKeyRef?] = []
    private var progressPanel: NSPanel?
    private var progressSessionID: UUID?
    private var progressStartedAt: Date?
    private var selectionMonitor: Any?
    private var instantEscapeMonitor: Any?
    private var instantSelectionText = ""
    private var lastInstantSelectionDate = Date.distantPast
    private var instantSelectionPoint = CGPoint.zero
    private var instantIconPanel: NSPanel?
    private var instantResultPanel: NSPanel?
    private var instantCardModel: InstantSelectionCardModel?
    private var instantActionTarget: InstantSelectionActionTarget?
    private var instantCloseTarget: InstantSelectionActionTarget?
    private var instantDismissWorkItem: DispatchWorkItem?
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
        configureInstantSelection(enabled: UserDefaults.standard.bool(forKey: "instantSelectionEnabled"))
    }

    func configureInstantSelection(enabled: Bool) {
        if let selectionMonitor { NSEvent.removeMonitor(selectionMonitor); self.selectionMonitor = nil }
        if let instantEscapeMonitor { NSEvent.removeMonitor(instantEscapeMonitor); self.instantEscapeMonitor = nil }
        hideInstantSelectionPanels()
        guard enabled else { return }
        selectionMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor in self?.handlePossibleInstantSelection(at: NSEvent.mouseLocation) }
        }
        instantEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.hideInstantSelectionPanels() }
        }
    }

    func reloadShortcuts(_ shortcuts: [ShortcutAction: ShortcutConfig]) {
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        refs.removeAll()
        let actions: [(ShortcutAction, UInt32)] = [(.input, 1), (.selection, 2), (.screenshot, 3), (.crossWriting, 4), (.openLiveCaption, 5), (.toggleLiveCaption, 6)]
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
        captureSelectedText(restoreClipboard: true, completion: { UsageMetrics.increment(.selectionTranslation); self.onSelection?($0) })
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
        let sessionID = UUID()
        progressSessionID = sessionID
        progressStartedAt = Date()
        let indicator = NSProgressIndicator(frame: NSRect(x: 14, y: 12, width: 242, height: 8))
        indicator.style = .bar
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        let label = NSTextField(labelWithString: "PallasOwl Translator 正在处理…")
        label.frame = NSRect(x: 14, y: 29, width: 242, height: 20)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: mouse.x, y: mouse.y, width: 270, height: 58)
        let originX = min(max(mouse.x + 14, visible.minX + 8), visible.maxX - 278)
        let originY = min(max(mouse.y - 66, visible.minY + 8), visible.maxY - 66)
        let panel = NSPanel(contentRect: NSRect(x: originX, y: originY, width: 270, height: 58),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.contentView?.addSubview(indicator)
        panel.contentView?.addSubview(label)
        panel.orderFrontRegardless()
        progressPanel = panel
    }

    func endCrossWritingProgress() {
        guard let sessionID = progressSessionID else { return }
        let elapsed = Date().timeIntervalSince(progressStartedAt ?? Date())
        let delay = max(0, 0.6 - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.progressSessionID == sessionID else { return }
            self.progressPanel?.orderOut(nil)
            self.progressPanel = nil
            self.progressSessionID = nil
            self.progressStartedAt = nil
        }
    }

    private func captureSelectedText(restoreClipboard: Bool, completion: @escaping (String) -> Void) {
        let pasteboard = NSPasteboard.general
        let old = pasteboard.string(forType: .string)
        let oldChange = pasteboard.changeCount
        postCommandC()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard pasteboard.changeCount != oldChange, let text = pasteboard.string(forType: .string), !text.isEmpty else {
                self.onError?("没有读取到选中文字。请确认已选中文字；如仍失败，请在“隐私与安全性 → 辅助功能”中重新添加 PallasOwl Translator。")
                return
            }
            completion(text)
            if restoreClipboard, let old { pasteboard.clearContents(); pasteboard.setString(old, forType: .string) }
        }
    }

    private func handlePossibleInstantSelection(at point: CGPoint) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        if let panel = instantResultPanel, panel.frame.contains(point) { return }
        if let panel = instantIconPanel, !panel.frame.contains(point) {
            hideInstantSelectionPanels()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            if let text = self.accessibilitySelectedText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.presentInstantSelection(text, at: point)
            } else {
                // “选中即译”不得模拟 Command+C。异步恢复剪贴板会与用户随后执行的
                // 复制、粘贴或右键菜单竞争；不支持辅助功能选区读取的 App 仍可使用
                // 用户主动触发的“划词翻译”快捷键。
                self.hideInstantSelectionPanels()
            }
        }
    }

    private func presentInstantSelection(_ text: String, at point: CGPoint) {
        guard text.count <= 5_000 else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2 else { return }
        if cleaned == instantSelectionText, Date().timeIntervalSince(lastInstantSelectionDate) < 1 { return }
        instantSelectionText = cleaned
        lastInstantSelectionDate = Date()
        instantSelectionPoint = point
        if UserDefaults.standard.bool(forKey: "instantSelectionAutomatic") { beginInstantTranslation() }
        else { showInstantTranslateIcon(at: point) }
    }

    private func accessibilitySelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success else { return nil }
        return selected as? String
    }

    private func showInstantTranslateIcon(at point: CGPoint) {
        hideInstantSelectionPanels()
        let target = InstantSelectionActionTarget { [weak self] in self?.beginInstantTranslation() }
        let button = InstantTranslateIconButton(image: MenuBarIcon.image, target: target, action: #selector(InstantSelectionActionTarget.trigger))
        button.isBordered = false
        button.imageScaling = .scaleProportionallyUpOrDown
        button.toolTip = "翻译"
        button.wantsLayer = true
        button.layer?.cornerRadius = 9
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor
        button.layer?.shadowColor = NSColor.black.cgColor
        button.layer?.shadowOpacity = 0.28
        button.layer?.shadowRadius = 4
        button.layer?.shadowOffset = CGSize(width: 0, height: -2)
        let iconSize = NSSize(width: 36, height: 36)
        let panel = makeInstantPanel(frame: NSRect(origin: panelOrigin(near: point, size: iconSize), size: iconSize))
        panel.backgroundColor = .clear
        panel.contentView = button
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.animator().alphaValue = 1
        instantActionTarget = target
        instantIconPanel = panel
    }

    private func beginInstantTranslation() {
        instantIconPanel?.orderOut(nil); instantIconPanel = nil
        let dictionaryCandidate = isDictionaryCandidate(instantSelectionText)
        let size = NSSize(width: 460, height: dictionaryCandidate ? 360 : 290)
        let model = instantCardModel ?? InstantSelectionCardModel()
        model.sourceText = instantSelectionText
        if let direction = onInstantLanguageDirection?() {
            model.sourceLanguage = direction.source
            model.targetLanguage = direction.target
        }
        model.translatedText = ""
        model.dictionaryText = nil
        model.dictionaryURL = nil
        model.errorMessage = nil
        model.isLoading = true
        model.showsSource = false
        model.close = { [weak self] in self?.hideInstantSelectionPanels() }
        model.retry = { [weak self] in self?.beginInstantTranslation() }
        model.speak = { [weak self, weak model] in guard let text = model?.translatedText else { return }; self?.onSpeakInstantSelection?(text) }
        model.openMainWindow = { [weak self] in guard let self else { return }; self.onOpenInstantSelectionMain?(self.instantSelectionText); self.hideInstantSelectionPanels() }
        instantCardModel = model
        let panel: NSPanel
        if let current = instantResultPanel {
            panel = current
            panel.setFrame(NSRect(origin: panelOrigin(near: instantSelectionPoint, size: size), size: size), display: true, animate: true)
        } else {
            panel = makeInstantPanel(frame: NSRect(origin: panelOrigin(near: instantSelectionPoint, size: size), size: size))
            panel.backgroundColor = .clear
            panel.contentView = NSHostingView(rootView: InstantSelectionCardView(model: model))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.18; panel.animator().alphaValue = 1 }
            instantResultPanel = panel
        }
        let panelID = ObjectIdentifier(panel)
        instantDismissWorkItem?.cancel()
        let dismiss = DispatchWorkItem { [weak self, weak model] in
            guard let self, let current = self.instantResultPanel, ObjectIdentifier(current) == panelID else { return }
            if model?.isHovered == true { self.scheduleInstantDismiss(panelID: panelID, after: 5) }
            else { self.hideInstantSelectionPanels() }
        }
        instantDismissWorkItem = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: dismiss)
        guard let onInstantSelection else { model.isLoading = false; model.errorMessage = "选中即译尚未就绪。"; return }
        onInstantSelection(instantSelectionText) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                let successfulTranslation = try? result.get()
                model.isLoading = false
                if let successfulTranslation { model.translatedText = successfulTranslation }
                else { model.errorMessage = "翻译失败，请检查当前翻译引擎。" }
                if successfulTranslation != nil { UsageMetrics.increment(.instantSelection) }
                guard dictionaryCandidate else { return }
                if let entry = try? await WiktionaryService().lookup(self.instantSelectionText) {
                    UsageMetrics.increment(.dictionaryLookup)
                    var details = "词典 · \(entry.language) · \(entry.partOfSpeech)\n\(entry.definition)"
                    if let example = entry.example, !example.isEmpty { details += "\n例句：\(example)" }
                    model.dictionaryText = details + "\n来源：Wiktionary"
                    model.dictionaryURL = WiktionaryService.pageURL(for: self.instantSelectionText)
                }
            }
        }
    }

    private func scheduleInstantDismiss(panelID: ObjectIdentifier, after delay: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.instantResultPanel, ObjectIdentifier(panel) == panelID else { return }
            if self.instantCardModel?.isHovered == true { self.scheduleInstantDismiss(panelID: panelID, after: 5) }
            else { self.hideInstantSelectionPanels() }
        }
        instantDismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func isDictionaryCandidate(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count <= 60, !cleaned.contains("\n") else { return false }
        return cleaned.split(whereSeparator: { $0.isWhitespace }).count <= 4 && cleaned.range(of: "[.!?。！？]$", options: .regularExpression) == nil
    }

    private func makeInstantPanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar; panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        return panel
    }

    private func panelOrigin(near point: CGPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        return NSPoint(x: min(max(point.x + 10, visible.minX + 8), visible.maxX - size.width - 8),
                       y: min(max(point.y - size.height - 10, visible.minY + 8), visible.maxY - size.height - 8))
    }

    private func hideInstantSelectionPanels() {
        instantIconPanel?.orderOut(nil); instantResultPanel?.orderOut(nil)
        instantDismissWorkItem?.cancel(); instantDismissWorkItem = nil
        instantIconPanel = nil; instantResultPanel = nil; instantCardModel = nil; instantActionTarget = nil; instantCloseTarget = nil
    }

    func captureScreenshot() {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            onError?("需要屏幕录制权限。授权后请重启 PallasOwl Translator，再按截图翻译快捷键。")
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
                    else { UsageMetrics.increment(.screenshotTranslation); self.onScreenshot?(text) }
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
        if id == 5 { onOpenLiveCaption?() }
        if id == 6 { onToggleLiveCaption?() }
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

private final class InstantSelectionActionTarget: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func trigger() { action() }
}
