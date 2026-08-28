import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("历史记录").font(.title2.bold())
                Spacer()
                Button("清空", role: .destructive, action: state.clearHistory).disabled(state.history.isEmpty)
            }
            .padding()
            List(state.history) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(item.mode.rawValue, systemImage: item.mode.systemIcon)
                        Spacer()
                        Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                    Text(item.source).lineLimit(2)
                    Text(item.result).foregroundStyle(.secondary).lineLimit(3)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

