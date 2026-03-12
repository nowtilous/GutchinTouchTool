import SwiftUI

struct GestureConsoleView: View {
    let entries: [GestureLogEntry]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.green)
                .font(.system(size: 11))

            if entries.isEmpty {
                Text("No gestures detected yet")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else {
                let recent = entries.suffix(5)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(recent)) { entry in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(colorForLevel(entry.level))
                                .frame(width: 5, height: 5)
                            Text(Self.timeFormatter.string(from: entry.timestamp))
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .foregroundStyle(colorForLevel(entry.level))
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        )
        .frame(minWidth: 350, maxWidth: 550)
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
