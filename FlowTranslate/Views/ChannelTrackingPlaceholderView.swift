import SwiftUI

struct ChannelTrackingPlaceholderView: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Label("建设中…", systemImage: "wrench.and.screwdriver.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule(style: .continuous)
                )
                .shadow(color: .orange.opacity(0.25), radius: 7, y: 3)

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.18), Color.purple.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 104, height: 104)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 43, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }

            VStack(spacing: 9) {
                Text("频道追踪")
                    .font(.title2.weight(.semibold))
                Text("持续关注重要频道，在发现新视频后自动转写并生成摘要。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                plannedRow("添加 YouTube 频道或创作者", icon: "person.crop.rectangle.stack")
                plannedRow("检测新视频并避免重复处理", icon: "arrow.triangle.2.circlepath")
                plannedRow("提取字幕或使用 Whisper 转写", icon: "captions.bubble")
                plannedRow("生成分级摘要并导出到 Obsidian", icon: "doc.text.magnifyingglass")
            }
            .padding(18)
            .frame(maxWidth: 470, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Label("当前仅展示功能规划，暂不执行后台监测", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func plannedRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.callout)
    }
}
