import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class InstantSelectionCardModel {
    var sourceText = ""
    var translatedText = ""
    var sourceLanguage = "自动检测"
    var targetLanguage = "简体中文"
    var dictionaryText: String?
    var dictionaryURL: URL?
    var isLoading = true
    var errorMessage: String?
    var showsSource = false
    var isHovered = false
    var retry: (() -> Void)?
    var close: (() -> Void)?
    var speak: (() -> Void)?
    var openMainWindow: (() -> Void)?
}

struct InstantSelectionCardView: View {
    @Bindable var model: InstantSelectionCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: MenuBarIcon.image)
                    .resizable().frame(width: 20, height: 20)
                Text("选中即译").font(.headline)
                Text("\(model.sourceLanguage) → \(model.targetLanguage)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.close?() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("关闭")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.isLoading {
                        HStack(spacing: 9) {
                            ProgressView().controlSize(.small)
                            Text("正在翻译…").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Button("重试") { model.retry?() }.buttonStyle(.borderedProminent)
                    } else {
                        Text(model.translatedText)
                            .font(.system(size: bodyFontSize))
                            .lineSpacing(bodyLineSpacing)
                            .textSelection(.enabled)
                        if let dictionary = model.dictionaryText {
                            Divider()
                            Text(dictionary)
                                .font(.system(size: max(13, bodyFontSize - 2)))
                                .lineSpacing(max(2, bodyLineSpacing - 1))
                                .foregroundStyle(.secondary)
                            if let url = model.dictionaryURL {
                                Link("在 Wiktionary 中查看", destination: url).font(.caption)
                            }
                        }
                    }

                    if model.showsSource {
                        Divider()
                        Text("原文").font(.caption).foregroundStyle(.secondary)
                        Text(model.sourceText)
                            .font(.system(size: max(13, bodyFontSize - 1)))
                            .lineSpacing(bodyLineSpacing)
                            .foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }

            Divider()
            HStack(spacing: 14) {
                Button(model.showsSource ? "收起原文" : "显示原文") {
                    withAnimation(.easeInOut(duration: 0.18)) { model.showsSource.toggle() }
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                actionButton("朗读", "speaker.wave.2") { model.speak?() }
                actionButton("复制", "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.translatedText, forType: .string)
                }
                actionButton("打开主窗口", "arrow.up.forward.app") { model.openMainWindow?() }
            }
            .font(.caption).padding(.horizontal, 16).padding(.vertical, 11)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .onHover { model.isHovered = $0 }
    }

    private var bodyFontSize: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: "editorFontSize") as? Double ?? 16)
    }

    private var bodyLineSpacing: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: "editorLineSpacing") as? Double ?? 5)
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol) }
            .buttonStyle(.plain).disabled(model.isLoading || model.translatedText.isEmpty)
    }
}

final class InstantTranslateIconButton: NSButton {
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area); tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            animator().frame = frame.insetBy(dx: -2, dy: -2)
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            animator().frame = frame.insetBy(dx: 2, dy: 2)
        }
    }
}
