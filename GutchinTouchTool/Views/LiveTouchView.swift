import SwiftUI

struct LiveTouchView: View {
    @ObservedObject private var touchState = LiveTouchState.shared
    @EnvironmentObject var appState: AppState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Trackpad outline — border changes on press
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .darkGray).opacity(touchState.isPressed ? 0.25 : 0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                touchState.isPressed
                                    ? appState.accentColorChoice.color.opacity(0.5)
                                    : Color.gray.opacity(0.3),
                                lineWidth: touchState.isPressed ? 1.5 : 1
                            )
                    )
                    .animation(.easeOut(duration: 0.15), value: touchState.isPressed)

                // Zone grid lines (subtle)
                Path { path in
                    let w = geo.size.width
                    let h = geo.size.height
                    path.move(to: CGPoint(x: w / 2, y: 8))
                    path.addLine(to: CGPoint(x: w / 2, y: h - 8))
                    path.move(to: CGPoint(x: 8, y: h / 2))
                    path.addLine(to: CGPoint(x: w - 8, y: h / 2))
                }
                .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)

                // Touch trails
                TouchTrailsView(
                    trails: touchState.trails,
                    geoSize: geo.size,
                    accentColor: appState.accentColorChoice.color
                )

                // Touch points
                ForEach(touchState.touches) { touch in
                    TouchDotView(
                        touch: touch,
                        geoSize: geo.size,
                        isPressed: touchState.isPressed,
                        accentColor: appState.accentColorChoice.color
                    )
                }

                // Press indicator label
                if !touchState.touches.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(touchState.isPressed ? "PRESS" : "TOUCH")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(
                                    touchState.isPressed
                                        ? appState.accentColorChoice.color
                                        : .secondary.opacity(0.5)
                                )
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(
                                            touchState.isPressed
                                                ? appState.accentColorChoice.color.opacity(0.15)
                                                : Color.gray.opacity(0.1)
                                        )
                                )
                                .animation(.easeOut(duration: 0.15), value: touchState.isPressed)
                        }
                    }
                    .padding(6)
                }

                // "No touches" hint
                if touchState.touches.isEmpty && touchState.trails.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "hand.point.up")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("Touch trackpad")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }
            }
        }
        .aspectRatio(1.4, contentMode: .fit)
    }
}

// MARK: - Touch Trails

private struct TouchTrailsView: View {
    let trails: [Int: [TrailPoint]]
    let geoSize: CGSize
    let accentColor: Color

    var body: some View {
        let now = ProcessInfo.processInfo.systemUptime
        Canvas { context, _ in
            for (_, trail) in trails {
                guard trail.count >= 2 else { continue }
                // Draw trail segments with fading opacity
                for i in 1..<trail.count {
                    let p0 = trail[i - 1]
                    let p1 = trail[i]
                    let age = now - p1.age
                    let opacity = max(0, 1.0 - age / 0.6) * 0.5

                    guard opacity > 0.01 else { continue }

                    let from = CGPoint(
                        x: CGFloat(p0.x) * geoSize.width,
                        y: (1 - CGFloat(p0.y)) * geoSize.height
                    )
                    let to = CGPoint(
                        x: CGFloat(p1.x) * geoSize.width,
                        y: (1 - CGFloat(p1.y)) * geoSize.height
                    )

                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)

                    let progress = Double(i) / Double(trail.count)
                    let lineWidth = 1.5 + progress * 2.5

                    context.stroke(
                        path,
                        with: .color(accentColor.opacity(opacity)),
                        lineWidth: lineWidth
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Touch Dot

private struct TouchDotView: View {
    let touch: TouchPoint
    let geoSize: CGSize
    let isPressed: Bool
    let accentColor: Color

    var body: some View {
        let x = CGFloat(touch.x) * geoSize.width
        let y = (1 - CGFloat(touch.y)) * geoSize.height
        let baseDot: CGFloat = max(12, min(24, CGFloat(touch.size) * 2.5))
        let dotSize: CGFloat = isPressed ? baseDot * 1.3 : baseDot
        let glowSize: CGFloat = isPressed ? dotSize * 2.8 : dotSize * 2

        ZStack {
            // Glow — larger and brighter on press
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accentColor.opacity(isPressed ? 0.7 : 0.4),
                            accentColor.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: glowSize / 2
                    )
                )
                .frame(width: glowSize, height: glowSize)

            // Dot
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentColor, accentColor.opacity(isPressed ? 0.8 : 0.6)],
                        center: .center,
                        startRadius: 0,
                        endRadius: dotSize / 2
                    )
                )
                .frame(width: dotSize, height: dotSize)
                .overlay(
                    Circle().stroke(
                        Color.white.opacity(isPressed ? 0.5 : 0.3),
                        lineWidth: isPressed ? 1.5 : 1
                    )
                )
        }
        .position(x: x, y: y)
    }
}
