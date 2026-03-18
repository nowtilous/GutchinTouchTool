import SwiftUI

private let tutorialStorageKey = "GTTHasSeenTutorial"

extension UserDefaults {
    static var hasSeenTutorial: Bool {
        get { UserDefaults.standard.bool(forKey: tutorialStorageKey) }
        set { UserDefaults.standard.set(newValue, forKey: tutorialStorageKey) }
    }
}

enum TutorialStep: Int, CaseIterable {
    case welcome = 0
    case sidebar
    case triggers
    case actions
    case config
    case tips
    case done

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .sidebar: return "Applications"
        case .triggers: return "Triggers"
        case .actions: return "Actions"
        case .config: return "Configuration"
        case .tips: return "Tips & Tricks"
        case .done: return "You're set!"
        }
    }

    var bodyText: String {
        switch self {
        case .welcome:
            return "GutchinTouchTool turns your trackpad into a programmable input surface.\n\nMap 30+ gesture types — swipes, taps, pinches, circles, edge slides — to keyboard shortcuts, window management, media controls, scripts, and more."
        case .sidebar:
            return "Choose which apps your gestures apply to.\n\n\"All Apps\" means global — gestures work everywhere.\n\nAdd specific apps (e.g. Safari, Xcode) for per-app bindings.\n\nTip: app-specific triggers override global ones."
        case .triggers:
            return "Your gesture bindings.\n\nPick from Trackpad, Keyboard, Mouse, or Drawing triggers.\n\nTrackpad offers 2–5 finger swipes, taps, pinches, TipTaps, edge slides, and corner clicks.\n\nClick {{plus}} to add a trigger."
        case .actions:
            return "What happens when a trigger fires.\n\nAdd one or more: Maximize Window, Send Keystroke, Volume Up/Down, Launch App, Run Script, Play/Pause, and 20+ more.\n\nClick {{plus}} to add an action."
        case .config:
            return "Edit the selected trigger or action here.\n\nRename triggers, enable/disable them, set \"Suppress Click\" for click-based gestures.\n\nConfigure action parameters (e.g. which key to send, which app to launch)."
        case .tips:
            return "Live Touch — finger positions for debugging.\n\nConsole — logs every detected gesture.\n\nMenu bar — click to open or toggle ON/OFF.\n\nGrant Accessibility & Automation permissions when prompted.\n\nTry: 3 Finger Swipe → Volume, Left Edge Slide → Brightness."
        case .done:
            return "Quick start: Add trigger → add actions → toggle ON.\n\nExport presets from Settings to share configs.\n\nEnjoy! 🖥️"
        }
    }

    var highlightRegion: TutorialRegion? {
        switch self {
        case .welcome: return nil
        case .sidebar: return .sidebar
        case .triggers: return .triggers
        case .actions: return .actions
        case .config: return .config
        case .tips: return nil
        case .done: return nil
        }
    }

    var isLast: Bool { self == .done }
}

enum TutorialRegion: String {
    case sidebar, triggers, actions, config
}

struct TutorialFramePreferenceKey: PreferenceKey {
    static var defaultValue: [TutorialRegion: CGRect] = [:]
    static func reduce(value: inout [TutorialRegion: CGRect], nextValue: () -> [TutorialRegion: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct TutorialAnchorModifier: ViewModifier {
    let region: TutorialRegion

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TutorialFramePreferenceKey.self,
                    value: [region: geo.frame(in: .named("tutorialOverlay"))]
                )
            }
        )
    }
}

extension View {
    func tutorialAnchor(_ region: TutorialRegion) -> some View {
        modifier(TutorialAnchorModifier(region: region))
    }
}

struct CutoutMaskShape: Shape {
    let fullRect: CGRect
    let cutout: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(fullRect)
        path.addRect(cutout)
        return path
    }
}

struct TutorialOverlayView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    var frames: [TutorialRegion: CGRect]
    @State private var currentStep: TutorialStep = .welcome

    private var highlightRect: CGRect? {
        guard let region = currentStep.highlightRegion else { return nil }
        return frames[region]
    }

    /// Card position: avoid obscuring the highlighted region. Subtle shift — not too far for easy Next clicks.
    private var cardAlignment: HorizontalAlignment {
        switch currentStep.highlightRegion {
        case .sidebar: return .trailing   // highlight left → card right
        case .triggers, .actions: return .trailing
        case .config: return .leading     // highlight right → card left
        case .none: return .center
        }
    }

    var body: some View {
        ZStack {
            // Dim overlay with spotlight cutout
            dimOverlay

            // Tutorial card — positioned to avoid obscuring the spotlight
            VStack {
                Spacer()
                HStack(spacing: 0) {
                    if cardAlignment == .trailing || cardAlignment == .center {
                        Spacer(minLength: 40)
                    }
                    tutorialCard
                    if cardAlignment == .leading || cardAlignment == .center {
                        Spacer(minLength: 40)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .allowsHitTesting(true)
    }

    private var dimOverlay: some View {
        GeometryReader { geo in
            let fullRect = CGRect(origin: .zero, size: geo.size)
            let cutout = highlightRect
            let hasValidCutout = cutout != nil && (cutout!.width > 20 && cutout!.height > 20)

            ZStack {
                Color.black.opacity(0.55)
                    .mask(
                        Group {
                            if hasValidCutout, let c = cutout {
                                cutoutMaskShape(fullRect: fullRect, cutout: c)
                            } else {
                                Rectangle()
                            }
                        }
                    )

                // Highlight ring around spotlight
                if hasValidCutout, let c = cutout {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(appState.accentColorChoice.color.opacity(0.8), lineWidth: 3)
                        .frame(width: c.width + 8, height: c.height + 8)
                        .position(x: c.midX, y: c.midY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func cutoutMaskShape(fullRect: CGRect, cutout: CGRect) -> some View {
        CutoutMaskShape(fullRect: fullRect, cutout: cutout)
            .fill(.white, style: FillStyle(eoFill: true))
    }

    private var tutorialCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(currentStep.title)
                    .font(.title2)
                ScrollView {
                    tutorialBodyText(currentStep.bodyText)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Divider()

            HStack {
                Button("Skip") {
                    UserDefaults.hasSeenTutorial = true
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                if currentStep.rawValue > 0 {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentStep = TutorialStep(rawValue: currentStep.rawValue - 1)!
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<TutorialStep.allCases.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentStep.rawValue ? appState.accentColorChoice.color : Color.gray.opacity(0.4))
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer()
                if currentStep.isLast {
                    Button("Got it!") {
                        UserDefaults.hasSeenTutorial = true
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.accentColorChoice.color)
                } else {
                    Button("Next") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentStep = TutorialStep(rawValue: currentStep.rawValue + 1)!
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.accentColorChoice.color)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
    }
}

// Renders body text with {{plus}} replaced by the actual SF Symbol
private func tutorialBodyText(_ text: String) -> Text {
    let parts = text.split(separator: "{{plus}}", omittingEmptySubsequences: false)
    if parts.count == 1 {
        return Text(text)
    }
    var result: Text = Text(parts[0])
    for i in 1..<parts.count {
        result = result + Text(Image(systemName: "plus")) + Text(parts[i])
    }
    return result
}

// Sheet-based tutorial (for Settings "Show Tutorial" - no highlight)
struct TutorialSheetView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var currentStep: TutorialStep = .welcome

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(currentStep.title)
                    .font(.title2)
                ScrollView {
                    tutorialBodyText(currentStep.bodyText)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Divider()

            HStack {
                Button("Skip") {
                    UserDefaults.hasSeenTutorial = true
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                if currentStep.rawValue > 0 {
                    Button("Back") {
                        currentStep = TutorialStep(rawValue: currentStep.rawValue - 1)!
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<TutorialStep.allCases.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentStep.rawValue ? appState.accentColorChoice.color : Color.gray.opacity(0.4))
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer()
                if currentStep.isLast {
                    Button("Done") { isPresented = false }
                        .buttonStyle(.borderedProminent)
                        .tint(appState.accentColorChoice.color)
                } else {
                    Button("Next") {
                        currentStep = TutorialStep(rawValue: currentStep.rawValue + 1)!
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.accentColorChoice.color)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 360)
    }
}

#Preview {
    TutorialOverlayView(isPresented: .constant(true), frames: [:])
        .environmentObject(AppState())
}
