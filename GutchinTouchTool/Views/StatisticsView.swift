import SwiftUI

struct StatisticsView: View {
    @ObservedObject var stats = GestureStatistics.shared
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                overviewCards
                gestureBreakdown
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gesture Statistics")
                    .font(.title.bold())
                Text("Tracking since \(stats.sessionStart, style: .date)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { stats.reset() }) {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Overview Cards

    private var overviewCards: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Total Detected",
                value: "\(stats.totalGestures)",
                icon: "hand.raised.fingers.spread.fill",
                color: .blue
            )
            StatCard(
                title: "Triggers Fired",
                value: "\(stats.totalFired)",
                icon: "bolt.fill",
                color: .green
            )
            StatCard(
                title: "Unmatched",
                value: "\(stats.unmatchedCount)",
                icon: "xmark.circle",
                color: .orange
            )
            StatCard(
                title: "Unique Gestures",
                value: "\(stats.uniqueGesturesCount)",
                icon: "hand.draw.fill",
                color: .purple
            )
        }
    }

    // MARK: - Gesture Breakdown

    private var gestureBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gesture Breakdown")
                .font(.headline)

            if stats.sortedEntries.isEmpty {
                Text("No gestures recorded yet. Start using trackpad gestures to see statistics.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                let maxCount = stats.sortedEntries.first?.totalCount ?? 1

                ForEach(stats.sortedEntries) { entry in
                    GestureStatRow(entry: entry, maxCount: maxCount, accentColor: appState.accentColorChoice.color)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Gesture Row

private struct GestureStatRow: View {
    let entry: GestureStatEntry
    let maxCount: Int
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.gesture)
                    .font(.system(.body, design: .rounded).weight(.medium))
                Spacer()
                if entry.firedCount > 0 {
                    Text("\(entry.firedCount) fired")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(4)
                }
                Text("\(entry.totalCount)")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                let fraction = maxCount > 0 ? CGFloat(entry.totalCount) / CGFloat(maxCount) : 0
                RoundedRectangle(cornerRadius: 3)
                    .fill(accentColor.opacity(0.7))
                    .frame(width: geo.size.width * fraction, height: 6)
            }
            .frame(height: 6)

            if let last = entry.lastDetected {
                Text("Last: \(last, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
