import AppKit
import Observation
import SwiftUI

struct CrossWritingProgressView: View {
    @State private var progressOffset: CGFloat = -120

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: MenuBarIcon.image)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .shadow(color: Color.purple.opacity(0.28), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 8) {
                Text("正在进行跨语写作…")
                    .font(.system(size: 13.5, weight: .semibold))
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.09))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [
                                    Color(red: 0.05, green: 0.78, blue: 0.98),
                                    Color(red: 0.50, green: 0.31, blue: 1.0),
                                    Color(red: 0.05, green: 0.78, blue: 0.98)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: max(72, geometry.size.width * 0.44))
                            .offset(x: progressOffset)
                            .shadow(color: Color.blue.opacity(0.25), radius: 3)
                    }
                    .clipShape(Capsule())
                    .onAppear {
                        progressOffset = -geometry.size.width * 0.45
                        withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                            progressOffset = geometry.size.width
                        }
                    }
                }
                .frame(height: 7)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(LinearGradient(
                colors: [Color.cyan.opacity(0.35), Color.purple.opacity(0.30)],
                startPoint: .leading,
                endPoint: .trailing
            ), lineWidth: 1))
        .shadow(color: .black.opacity(0.20), radius: 14, y: 6)
    }
}

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
        .onHover { hovered in
            model.isHovered = hovered
            guard !hovered else { return }
            // A short grace period prevents accidental dismissal while the pointer
            // crosses the rounded edge, but closes the card once it has truly left.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                if !model.isHovered { model.close?() }
            }
        }
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
