import SwiftUI

private struct ThemeColorKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    var themeColor: Color {
        get { self[ThemeColorKey.self] }
        set { self[ThemeColorKey.self] = newValue }
    }
}

struct GesturePreviewView: View {
    let gesture: TrackpadGesture
    @EnvironmentObject var appState: AppState
    @State private var animating = false
    @State private var animationID = UUID()

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Trackpad body
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .darkGray).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1.5)
                    )

                // Gesture animation
                gestureAnimation
                    .id(animationID)
            }
            .frame(width: 180, height: 140)
            .onAppear { startAnimation() }
            .onChange(of: gesture) { _ in restartAnimation() }

            Text(gesture.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .environment(\.themeColor, appState.accentColorChoice.color)
    }

    private func startAnimation() {
        animating = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation { animating = true }
        }
    }

    private func restartAnimation() {
        animating = false
        animationID = UUID()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation { animating = true }
        }
    }

    @ViewBuilder
    private var gestureAnimation: some View {
        switch gesture {
        // Swipes
        case .twoFingerSwipeUp:
            SwipeAnimation(fingerCount: 2, direction: .up, animating: animating)
        case .twoFingerSwipeDown:
            SwipeAnimation(fingerCount: 2, direction: .down, animating: animating)
        case .twoFingerSwipeLeft:
            SwipeAnimation(fingerCount: 2, direction: .left, animating: animating)
        case .twoFingerSwipeRight:
            SwipeAnimation(fingerCount: 2, direction: .right, animating: animating)
        case .threeFingerSwipeUp:
            SwipeAnimation(fingerCount: 3, direction: .up, animating: animating)
        case .threeFingerSwipeDown:
            SwipeAnimation(fingerCount: 3, direction: .down, animating: animating)
        case .threeFingerSwipeLeft:
            SwipeAnimation(fingerCount: 3, direction: .left, animating: animating)
        case .threeFingerSwipeRight:
            SwipeAnimation(fingerCount: 3, direction: .right, animating: animating)
        case .fourFingerSwipeUp:
            SwipeAnimation(fingerCount: 4, direction: .up, animating: animating)
        case .fourFingerSwipeDown:
            SwipeAnimation(fingerCount: 4, direction: .down, animating: animating)
        case .fourFingerSwipeLeft:
            SwipeAnimation(fingerCount: 4, direction: .left, animating: animating)
        case .fourFingerSwipeRight:
            SwipeAnimation(fingerCount: 4, direction: .right, animating: animating)

        // Taps
        case .twoFingerTap:
            TapAnimation(fingerCount: 2, animating: animating)
        case .twoFingerDoubleTap:
            DoubleTapAnimation(fingerCount: 2, animating: animating)
        case .threeFingerTap:
            TapAnimation(fingerCount: 3, animating: animating)
        case .fourFingerTap:
            TapAnimation(fingerCount: 4, animating: animating)
        case .fiveFingerTap:
            TapAnimation(fingerCount: 5, animating: animating)

        // Clicks
        case .twoFingerClick:
            TapAnimation(fingerCount: 2, animating: animating, isClick: true)
        case .threeFingerClick:
            TapAnimation(fingerCount: 3, animating: animating, isClick: true)

        // Pinch
        case .twoFingerPinchIn:
            PinchAnimation(pinchIn: true, animating: animating)
        case .twoFingerPinchOut:
            PinchAnimation(pinchIn: false, animating: animating)

        // Rotate
        case .twoFingerRotateLeft:
            RotateAnimation(clockwise: false, animating: animating)
        case .twoFingerRotateRight:
            RotateAnimation(clockwise: true, animating: animating)

        // TipTap
        case .tipTapLeft:
            TipTapAnimation(direction: .left, animating: animating)
        case .tipTapRight:
            TipTapAnimation(direction: .right, animating: animating)
        case .tipTapMiddle:
            TipTapAnimation(direction: .middle, animating: animating)

        // Circle
        case .circleClockwise:
            CircleAnimation(clockwise: true, animating: animating)
        case .circleCounterClockwise:
            CircleAnimation(clockwise: false, animating: animating)

        // Corner/Position clicks
        case .cornerClickTopLeft:
            PositionClickAnimation(position: .topLeft, animating: animating)
        case .cornerClickTopRight:
            PositionClickAnimation(position: .topRight, animating: animating)
        case .cornerClickBottomLeft:
            PositionClickAnimation(position: .bottomLeft, animating: animating)
        case .cornerClickBottomRight:
            PositionClickAnimation(position: .bottomRight, animating: animating)
        case .middleClickTop:
            PositionClickAnimation(position: .middleTop, animating: animating)
        case .middleClickBottom:
            PositionClickAnimation(position: .middleBottom, animating: animating)
        }
    }
}

// MARK: - Finger dot

struct FingerDot: View {
    var size: CGFloat = 18
    var opacity: Double = 1.0
    var isClick: Bool = false
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        themeColor.opacity(0.9),
                        themeColor.opacity(0.4)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(themeColor, lineWidth: isClick ? 2 : 0.5)
            )
            .shadow(color: themeColor.opacity(0.5), radius: 4)
            .opacity(opacity)
    }
}

// MARK: - Swipe Animation

struct SwipeAnimation: View {
    let fingerCount: Int
    let direction: SwipeDir
    let animating: Bool
    @Environment(\.themeColor) private var themeColor

    enum SwipeDir { case up, down, left, right }

    var body: some View {
        let spacing: CGFloat = 14
        let totalWidth = CGFloat(fingerCount - 1) * spacing

        ZStack {
            ForEach(0..<fingerCount, id: \.self) { i in
                let baseX = -totalWidth / 2 + CGFloat(i) * spacing
                FingerDot()
                    .offset(
                        x: baseX + (animating ? offsetX : 0),
                        y: animating ? offsetY : 0
                    )
            }

            // Arrow trail
            Image(systemName: arrowName)
                .font(.system(size: 20, weight: .light))
                .foregroundColor(themeColor.opacity(animating ? 0.6 : 0))
                .offset(
                    x: animating ? offsetX * 0.4 : 0,
                    y: animating ? offsetY * 0.4 : 0
                )
        }
        .animation(
            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
            value: animating
        )
    }

    private var offsetX: CGFloat {
        switch direction {
        case .left: return -30
        case .right: return 30
        default: return 0
        }
    }

    private var offsetY: CGFloat {
        switch direction {
        case .up: return -30
        case .down: return 30
        default: return 0
        }
    }

    private var arrowName: String {
        switch direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }
}

// MARK: - Tap Animation

struct TapAnimation: View {
    let fingerCount: Int
    let animating: Bool
    var isClick: Bool = false
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        let spacing: CGFloat = 14
        let totalWidth = CGFloat(fingerCount - 1) * spacing

        ZStack {
            // Ripple
            ForEach(0..<fingerCount, id: \.self) { i in
                let x = -totalWidth / 2 + CGFloat(i) * spacing
                Circle()
                    .stroke(themeColor.opacity(animating ? 0 : 0.4), lineWidth: 1.5)
                    .frame(width: animating ? 40 : 18, height: animating ? 40 : 18)
                    .offset(x: x)
            }

            ForEach(0..<fingerCount, id: \.self) { i in
                let x = -totalWidth / 2 + CGFloat(i) * spacing
                FingerDot(opacity: animating ? 1.0 : 0.3, isClick: isClick)
                    .scaleEffect(animating ? 1.0 : 0.6)
                    .offset(x: x)
            }
        }
        .animation(
            .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
            value: animating
        )
    }
}

// MARK: - Double Tap Animation

struct DoubleTapAnimation: View {
    let fingerCount: Int
    let animating: Bool
    @Environment(\.themeColor) private var themeColor
    @State private var phase: Int = 0

    var body: some View {
        let spacing: CGFloat = 14
        let totalWidth = CGFloat(fingerCount - 1) * spacing

        ZStack {
            ForEach(0..<fingerCount, id: \.self) { i in
                let x = -totalWidth / 2 + CGFloat(i) * spacing
                FingerDot(opacity: phase > 0 ? 1.0 : 0.3)
                    .scaleEffect(phase > 0 ? 1.0 : 0.6)
                    .offset(x: x)
            }

            // "x2" badge
            Text("x2")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(themeColor)
                .offset(y: 28)
                .opacity(phase == 2 ? 1 : 0)
        }
        .onAppear { runDoubleTap() }
        .onChange(of: animating) { _ in runDoubleTap() }
    }

    private func runDoubleTap() {
        phase = 0
        func tap(at time: Double, p: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                withAnimation(.easeInOut(duration: 0.15)) { phase = p }
            }
        }
        tap(at: 0.3, p: 1)
        tap(at: 0.5, p: 0)
        tap(at: 0.7, p: 2)
        tap(at: 0.9, p: 0)
        // Loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { runDoubleTap() }
    }
}

// MARK: - Pinch Animation

struct PinchAnimation: View {
    let pinchIn: Bool
    let animating: Bool

    var body: some View {
        let spread: CGFloat = pinchIn ? 30 : 10
        let closed: CGFloat = pinchIn ? 10 : 30

        ZStack {
            FingerDot()
                .offset(x: animating ? -closed : -spread, y: animating ? -closed : -spread)
            FingerDot()
                .offset(x: animating ? closed : spread, y: animating ? closed : spread)
        }
        .animation(
            .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
            value: animating
        )
    }
}

// MARK: - Rotate Animation

struct RotateAnimation: View {
    let clockwise: Bool
    let animating: Bool

    var body: some View {
        ZStack {
            FingerDot()
                .offset(x: 0, y: -18)
            FingerDot()
                .offset(x: 0, y: 18)
        }
        .rotationEffect(.degrees(animating ? (clockwise ? 45 : -45) : 0))
        .animation(
            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
            value: animating
        )
    }
}

// MARK: - TipTap Animation

struct TipTapAnimation: View {
    enum TipTapDir { case left, right, middle }
    let direction: TipTapDir
    let animating: Bool
    @State private var tapping = false

    var body: some View {
        ZStack {
            switch direction {
            case .left:
                // Right finger rests, left taps
                FingerDot(size: 16, opacity: 0.5)
                    .offset(x: 16)
                FingerDot(opacity: tapping ? 1.0 : 0.2)
                    .scaleEffect(tapping ? 1.0 : 0.5)
                    .offset(x: -16, y: tapping ? 0 : -12)
            case .right:
                // Left finger rests, right taps
                FingerDot(size: 16, opacity: 0.5)
                    .offset(x: -16)
                FingerDot(opacity: tapping ? 1.0 : 0.2)
                    .scaleEffect(tapping ? 1.0 : 0.5)
                    .offset(x: 16, y: tapping ? 0 : -12)
            case .middle:
                // Two fingers rest, one taps between
                FingerDot(size: 16, opacity: 0.5)
                    .offset(x: -22)
                FingerDot(size: 16, opacity: 0.5)
                    .offset(x: 22)
                FingerDot(opacity: tapping ? 1.0 : 0.2)
                    .scaleEffect(tapping ? 1.0 : 0.5)
                    .offset(y: tapping ? 0 : -12)
            }
        }
        .onAppear { runTipTap() }
    }

    private func runTipTap() {
        withAnimation(.easeOut(duration: 0.2)) { tapping = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeIn(duration: 0.2)) { tapping = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { runTipTap() }
    }
}

// MARK: - Circle Animation

struct CircleAnimation: View {
    let clockwise: Bool
    let animating: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            CircleAnimationContent(
                clockwise: clockwise,
                date: timeline.date
            )
        }
    }
}

private struct CircleAnimationContent: View {
    let clockwise: Bool
    let date: Date
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        let t = date.timeIntervalSinceReferenceDate
        let period: Double = 2.0
        let progress = t.truncatingRemainder(dividingBy: period) / period
        let p = CGFloat(progress)
        let radius: CGFloat = 30

        ZStack {
            circlePath(radius: radius)
            circleTrail(p: p, radius: radius)
            directionArrow
            fingerDot(p: p, radius: radius)
        }
    }

    private func circlePath(radius: CGFloat) -> some View {
        Circle()
            .stroke(themeColor.opacity(0.15), lineWidth: 2)
            .frame(width: radius * 2, height: radius * 2)
    }

    private func circleTrail(p: CGFloat, radius: CGFloat) -> some View {
        let trimFrom = max(0, p - 0.25)
        let scaleX: CGFloat = clockwise ? 1 : -1
        return Circle()
            .trim(from: trimFrom, to: p)
            .stroke(
                themeColor.opacity(0.4),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.degrees(-90))
            .scaleEffect(x: scaleX, y: 1)
    }

    private var directionArrow: some View {
        let name = clockwise ? "arrow.clockwise" : "arrow.counterclockwise"
        return Image(systemName: name)
            .font(.system(size: 14, weight: .light))
            .foregroundColor(themeColor.opacity(0.3))
    }

    private func fingerDot(p: CGFloat, radius: CGFloat) -> some View {
        let dir: CGFloat = clockwise ? 1 : -1
        let angle = .pi * 2 * p * dir - .pi / 2
        let x = radius * cos(angle)
        let y = radius * sin(angle)
        return FingerDot(size: 16)
            .offset(x: x, y: y)
    }
}

// MARK: - Position Click Animation

struct PositionClickAnimation: View {
    enum Position {
        case topLeft, topRight, bottomLeft, bottomRight, middleTop, middleBottom
    }
    let position: Position
    let animating: Bool
    @Environment(\.themeColor) private var themeColor
    @State private var pressing = false

    var body: some View {
        ZStack {
            // Zone highlight
            RoundedRectangle(cornerRadius: 4)
                .fill(themeColor.opacity(pressing ? 0.25 : 0.08))
                .frame(width: zoneW, height: zoneH)
                .offset(x: zoneX, y: zoneY)

            // Finger
            FingerDot(opacity: pressing ? 1.0 : 0.4)
                .scaleEffect(pressing ? 1.0 : 0.7)
                .offset(x: dotX, y: dotY)

            // Press ripple
            Circle()
                .stroke(themeColor.opacity(pressing ? 0 : 0.3), lineWidth: 1.5)
                .frame(width: pressing ? 36 : 16, height: pressing ? 36 : 16)
                .offset(x: dotX, y: dotY)
        }
        .onAppear { runPress() }
    }

    private func runPress() {
        withAnimation(.easeOut(duration: 0.25)) { pressing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeIn(duration: 0.25)) { pressing = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { runPress() }
    }

    private var dotX: CGFloat {
        switch position {
        case .topLeft, .bottomLeft: return -55
        case .topRight, .bottomRight: return 55
        case .middleTop, .middleBottom: return 0
        }
    }

    private var dotY: CGFloat {
        switch position {
        case .topLeft, .topRight, .middleTop: return -40
        case .bottomLeft, .bottomRight, .middleBottom: return 40
        }
    }

    private var zoneX: CGFloat { dotX }
    private var zoneY: CGFloat { dotY }

    private var zoneW: CGFloat {
        switch position {
        case .middleTop, .middleBottom: return 80
        default: return 40
        }
    }

    private var zoneH: CGFloat { 30 }
}
