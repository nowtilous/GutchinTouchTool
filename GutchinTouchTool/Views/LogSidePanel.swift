import SwiftUI

struct LogSidePanel: View {
    let entries: [GestureLogEntry]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(.green)
                Text("Console")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: { GestureLog.shared.entries.removeAll() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: entries.count) { _, _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(Color(nsColor: .separatorColor)),
            alignment: .leading
        )
    }
}

private struct LogEntryRow: View {
    let entry: GestureLogEntry
    @State private var ripple = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Circle()
                .fill(colorForLevel(entry.level))
                .frame(width: 6, height: 6)
                .padding(.top, 4)
                .overlay(
                    Circle()
                        .stroke(colorForLevel(entry.level).opacity(ripple ? 0 : 0.6), lineWidth: 1.5)
                        .frame(width: ripple ? 20 : 6, height: ripple ? 20 : 6)
                        .opacity(entry.level == .fire ? 1 : 0)
                )

            Text(Self.timeFormatter.string(from: entry.timestamp))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

            Text(entry.message)
                .foregroundStyle(colorForLevel(entry.level))
                .textSelection(.enabled)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            entry.level == .fire
                ? colorForLevel(entry.level).opacity(ripple ? 0 : 0.08)
                : Color.clear
        )
        .onAppear {
            if entry.level == .fire {
                withAnimation(.easeOut(duration: 0.6)) {
                    ripple = true
                }
            }
        }
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .detect:  return .cyan
        case .fire:    return .green
        case .action:  return .orange
        case .noMatch: return Color(nsColor: .tertiaryLabelColor)
        case .error:   return .red
        }
    }
}
