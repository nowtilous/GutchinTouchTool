import Foundation
import AppKit

// MARK: - Private MultitouchSupport.framework bindings
// Uses the same private framework approach as BetterTouchTool to detect trackpad touches system-wide

typealias MTDeviceRef = UnsafeMutableRawPointer

struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32        // 1=not touching, 2=starting, 3=hovering, 4=touching, 5=leaving, 6=invalid, 7=lifted
    var fingerID: Int32
    var handID: Int32
    var normalizedPosition: (x: Float, y: Float)
    var totalPressure: Float
    var pressure: Float
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolutePosition: (x: Float, y: Float)
    var unknown1: Int32
    var unknown2: Int32
    var density: Float
}

typealias MTContactCallbackFunction = @convention(c) (
    MTDeviceRef?,               // device
    UnsafeMutableRawPointer?,   // touches (pointer to array of MTTouch)
    Int32,                      // numTouches
    Double,                     // timestamp
    Int32                       // frame
) -> Void

// Dynamically load MultitouchSupport.framework
private let multitouchFramework: UnsafeMutableRawPointer? = {
    dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)
}()

// Function pointer types matching the C signatures
private typealias MTDeviceCreateListFunc = @convention(c) () -> Unmanaged<CFArray>
private typealias MTRegisterContactFrameCallbackFunc = @convention(c) (MTDeviceRef, MTContactCallbackFunction) -> Void
private typealias MTUnregisterContactFrameCallbackFunc = @convention(c) (MTDeviceRef, MTContactCallbackFunction) -> Void
private typealias MTDeviceStartFunc = @convention(c) (MTDeviceRef, Int32) -> Void
private typealias MTDeviceStopFunc = @convention(c) (MTDeviceRef) -> Void

private let _MTDeviceCreateList: MTDeviceCreateListFunc? = {
    guard let fw = multitouchFramework, let sym = dlsym(fw, "MTDeviceCreateList") else { return nil }
    return unsafeBitCast(sym, to: MTDeviceCreateListFunc.self)
}()

private let _MTRegisterContactFrameCallback: MTRegisterContactFrameCallbackFunc? = {
    guard let fw = multitouchFramework, let sym = dlsym(fw, "MTRegisterContactFrameCallback") else { return nil }
    return unsafeBitCast(sym, to: MTRegisterContactFrameCallbackFunc.self)
}()

private let _MTUnregisterContactFrameCallback: MTUnregisterContactFrameCallbackFunc? = {
    guard let fw = multitouchFramework, let sym = dlsym(fw, "MTUnregisterContactFrameCallback") else { return nil }
    return unsafeBitCast(sym, to: MTUnregisterContactFrameCallbackFunc.self)
}()

private let _MTDeviceStart: MTDeviceStartFunc? = {
    guard let fw = multitouchFramework, let sym = dlsym(fw, "MTDeviceStart") else { return nil }
    return unsafeBitCast(sym, to: MTDeviceStartFunc.self)
}()

private let _MTDeviceStop: MTDeviceStopFunc? = {
    guard let fw = multitouchFramework, let sym = dlsym(fw, "MTDeviceStop") else { return nil }
    return unsafeBitCast(sym, to: MTDeviceStopFunc.self)
}()

// MARK: - Global callback bridge

// We need a C-callable function; use a global to bridge to our instance
private var sharedTrackpadMonitor: TrackpadMonitor?

private let touchCallback: MTContactCallbackFunction = { device, touchesPtr, numTouches, timestamp, frame in
    guard let monitor = sharedTrackpadMonitor else { return }
    monitor.handleMultitouchFrame(rawTouches: touchesPtr, numTouches: Int(numTouches), timestamp: timestamp)
}


// MARK: - TrackpadMonitor

class TrackpadMonitor {
    private var monitors: [Any] = []
    private var registeredTriggers: [(id: UUID, gesture: TrackpadGesture, actions: [TriggerAction], appBundleID: String?, suppressClick: Bool)] = []
    private var devices: [MTDeviceRef] = []
    private var multitouchActive = false

    // Click suppression via CGEventTap
    private var clickSuppressEventTap: CFMachPort?
    private var clickSuppressRunLoopSource: CFRunLoopSource?
    private static var pendingSuppressClick = false
    private static var activeTrackpadMonitor: TrackpadMonitor?

    // Swipe tracking
    private var scrollDeltaX: CGFloat = 0
    private var scrollDeltaY: CGFloat = 0
    private var scrollFingerCount: Int = 0
    private var scrollStartTime: Date?
    private let swipeThreshold: CGFloat = 50
    // Minimum velocity (points/sec) for a swipe to fire — per-gesture, fast flick vs slow scroll
    private func swipeMinVelocity(for gesture: TrackpadGesture) -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: "GTTSwipeMinVelocity_\(gesture.rawValue)")
        return stored > 0 ? CGFloat(stored) : 500
    }

    // Press-drag tracking
    private var pressDragDeltaX: CGFloat = 0
    private var pressDragActive = false

    // Pinch/rotate tracking
    private var magnification: CGFloat = 0
    private var rotation: CGFloat = 0

    // Tap detection state
    private var touchBegan: Date?
    private var peakFingers: Int = 0
    private var currentFingers: Int = 0
    private var gestureConsumed = false
    private let tapTimeout: TimeInterval = 0.35
    private var totalMovement: Float = 0
    private var previousPositions: [Int32: (Float, Float)] = [:] // fingerID -> (x, y)
    private let tapMovementThreshold: Float = 0.05 // normalized units

    // Double-tap detection state
    private var lastTwoFingerTapTime: Date?
    private var doubleTapTimer: DispatchWorkItem?
    private let doubleTapWindow: TimeInterval = 0.4

    // TipTap detection state
    // TipTap = one finger resting on trackpad, another finger taps briefly
    // Sequence: 0→1 (rest) ... 1→2 (tap lands) ... 2→1 or 2→0→1 (tap lifts)
    private var oneFingerRestX: Float?        // X position of the resting finger
    private var oneFingerStartTime: Date?     // when 1-finger phase began
    private var twoFingerStartTime: Date?     // when 2nd finger appeared
    private var hadOneFingerRest = false      // did we have a 1-finger phase before going to 2?
    private var tipTapPending = false         // we saw 1→2 with a valid rest, waiting for 2→1 or 2→0→1
    private var tipTapPendingTime: Date?      // when the 2-finger phase started (for timeout)
    private let tipTapMaxTapDuration: TimeInterval = 0.35 // max time the tapping finger can be down
    private var tipTapMinRestTime: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "GTTTipTapMinRestTime")
        return stored > 0 ? stored : 0.12
    }
    private var lastTipTapFiredTime: Date?                // cooldown: prevent false fires when switching sides
    private let tipTapCooldown: TimeInterval = 0.25       // min time between consecutive TipTap fires

    // TipTap Middle: 2 fingers resting, one taps between them (2→3→2)
    private var twoFingerRestTime: Date?       // when 2-finger resting phase started
    private var threeFingerStartTime: Date?    // when 3rd finger appeared
    private var tipTapMiddlePending = false

    // Circle gesture detection (1-finger circular motion)
    private var circlePoints: [(x: Float, y: Float)] = []  // recent path points
    private var circleCumulativeAngle: Float = 0            // accumulated angle (radians)
    private var circleLastAngle: Float?                     // last angle to center
    private var circleCenterX: Float = 0                    // running centroid X
    private var circleCenterY: Float = 0                    // running centroid Y
    private let circleMinPoints: Int = 12                   // min points before checking
    private var circleLastFiredAngle: Float = 0             // cumulative angle at last fire
    private var circleStartTime: Date?                      // when circling started
    private var circleFireCount: Int = 0                    // how many times we've fired this session
    private var trackpadIsPressed = false                   // true when trackpad is clicked down
    private var circleDrawingActive = false                 // true while circle or edge slide mouse suppression is active
    private var mouseEventTap: CFMachPort?                  // CGEvent tap for suppressing mouse during circle or edge slide
    private var mouseEventTapRunLoopSource: CFRunLoopSource?

    private enum MouseSuppressionReason {
        case none
        case circle
        case edgeSlide
    }
    private var mouseSuppressionReason: MouseSuppressionReason = .none

    // Active gesture flags based on registered triggers with actions
    private var hasCircleClockwise = false
    private var hasCircleCounterClockwise = false
    private var hasCircleTriggers = false
    private var hasTriangleTriggers = false
    private var hasEdgeSlideTriggers = false
    private var has1FingerDrawGestures = false

    private var hasTwoFingerSwipe = false
    private var hasThreeFingerSwipe = false
    private var hasFourFingerSwipe = false
    private var hasSwipeTriggers = false

    private var hasPinchTriggers = false
    private var hasRotateTriggers = false
    private var hasPressDragTriggers = false

    private var hasTipTapLeft = false
    private var hasTipTapRight = false
    private var hasTipTapTriggers = false
    private var hasTipTapMiddle = false

    private var hasTwoFingerTap = false
    private var hasTwoFingerDoubleTap = false
    private var hasThreeFingerTap = false
    private var hasFourFingerTap = false
    private var hasFiveFingerTap = false
    private var hasTapTriggers = false

    private var hasPositionClickTriggers = false
    private var hasTwoFingerClick = false
    private var hasThreeFingerClick = false
    private var hasClickTriggers = false

    private var circleSumX: Float = 0
    private var circleSumY: Float = 0
    private var lastVisualizerUpdateTime: Double = 0
    private let visualizerMinInterval: Double = 1.0 / 60.0

    var isMouseSuppressedForTest: Bool {
        circleDrawingActive
    }

    var isMultitouchActiveForTest: Bool {
        multitouchActive
    }

    private var visualizerObserver: Any?

    init() {
        visualizerObserver = NotificationCenter.default.addObserver(
            forName: .visualizerStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateMultitouchMonitoringState()
        }
    }

    // Triangle gesture detection (1-finger pressing down and drawing)
    private var trianglePoints: [(x: Float, y: Float)] = []
    private var triangleFired = false

    // Edge slider detection (1-finger press + slide along edge, fires repeatedly)
    private var edgeSlideLastY: Float?
    private var edgeSlideEdge: EdgeSide?
    private let edgeSlideZoneWidth: Float = 0.08   // leftmost/rightmost 8% (edge margin)
    private let edgeSlideStep: Float = 0.04        // fire every ~4% of trackpad height

    private enum EdgeSide { case left, right }

    // Position click detection (1-finger click at specific zone)
    private var lastSingleFingerPos: (x: Float, y: Float)?  // last known 1-finger position
    private var positionClickFired = false                   // prevent re-firing on same press

    // Raw touch struct stride (auto-detected at runtime)
    private var touchStride: Int = 0

    func registerTriggers(_ triggers: [Trigger]) {
        unregisterAll()

        let trackpadTriggers = triggers.filter {
            if case .trackpadGesture = $0.input {
                return $0.isEnabled && (!$0.actions.isEmpty || $0.suppressClick)
            }
            return false
        }

        for trigger in trackpadTriggers {
            if case .trackpadGesture(let gesture) = trigger.input {
                registeredTriggers.append((id: trigger.id, gesture: gesture, actions: trigger.actions, appBundleID: trigger.appBundleID, suppressClick: trigger.suppressClick))
            }
        }

        guard !registeredTriggers.isEmpty else {
            NSLog("[TrackpadMonitor] No active triggers with actions configured")
            return
        }

        let configuredGestures = Set(registeredTriggers.map { $0.gesture })

        hasCircleClockwise = configuredGestures.contains(.circleClockwise)
        hasCircleCounterClockwise = configuredGestures.contains(.circleCounterClockwise)
        hasCircleTriggers = hasCircleClockwise || hasCircleCounterClockwise

        hasTriangleTriggers = configuredGestures.contains(.drawTriangle)

        hasEdgeSlideTriggers = configuredGestures.contains(.leftEdgeSlideUp) ||
                               configuredGestures.contains(.leftEdgeSlideDown) ||
                               configuredGestures.contains(.rightEdgeSlideUp) ||
                               configuredGestures.contains(.rightEdgeSlideDown)

        has1FingerDrawGestures = hasCircleTriggers || hasTriangleTriggers || hasEdgeSlideTriggers

        hasTwoFingerSwipe = configuredGestures.contains(.twoFingerSwipeUp) ||
                            configuredGestures.contains(.twoFingerSwipeDown) ||
                            configuredGestures.contains(.twoFingerSwipeLeft) ||
                            configuredGestures.contains(.twoFingerSwipeRight)

        hasThreeFingerSwipe = configuredGestures.contains(.threeFingerSwipeUp) ||
                              configuredGestures.contains(.threeFingerSwipeDown) ||
                              configuredGestures.contains(.threeFingerSwipeLeft) ||
                              configuredGestures.contains(.threeFingerSwipeRight)

        hasFourFingerSwipe = configuredGestures.contains(.fourFingerSwipeUp) ||
                             configuredGestures.contains(.fourFingerSwipeDown) ||
                             configuredGestures.contains(.fourFingerSwipeLeft) ||
                             configuredGestures.contains(.fourFingerSwipeRight)

        hasSwipeTriggers = hasTwoFingerSwipe || hasThreeFingerSwipe || hasFourFingerSwipe

        hasPinchTriggers = configuredGestures.contains(.twoFingerPinchIn) || configuredGestures.contains(.twoFingerPinchOut)
        hasRotateTriggers = configuredGestures.contains(.twoFingerRotateLeft) || configuredGestures.contains(.twoFingerRotateRight)
        hasPressDragTriggers = configuredGestures.contains(.twoFingerPressDragLeft) || configuredGestures.contains(.twoFingerPressDragRight)

        hasTipTapLeft = configuredGestures.contains(.tipTapLeft)
        hasTipTapRight = configuredGestures.contains(.tipTapRight)
        hasTipTapTriggers = hasTipTapLeft || hasTipTapRight
        hasTipTapMiddle = configuredGestures.contains(.tipTapMiddle)

        hasTwoFingerTap = configuredGestures.contains(.twoFingerTap)
        hasTwoFingerDoubleTap = configuredGestures.contains(.twoFingerDoubleTap)
        hasThreeFingerTap = configuredGestures.contains(.threeFingerTap)
        hasFourFingerTap = configuredGestures.contains(.fourFingerTap)
        hasFiveFingerTap = configuredGestures.contains(.fiveFingerTap)
        hasTapTriggers = hasTwoFingerTap || hasTwoFingerDoubleTap || hasThreeFingerTap || hasFourFingerTap || hasFiveFingerTap

        hasPositionClickTriggers = configuredGestures.contains(.cornerClickTopLeft) ||
                                   configuredGestures.contains(.cornerClickTopRight) ||
                                   configuredGestures.contains(.cornerClickBottomLeft) ||
                                   configuredGestures.contains(.cornerClickBottomRight) ||
                                   configuredGestures.contains(.middleClickTop) ||
                                   configuredGestures.contains(.middleClickBottom)

        hasTwoFingerClick = configuredGestures.contains(.twoFingerClick)
        hasThreeFingerClick = configuredGestures.contains(.threeFingerClick)
        hasClickTriggers = hasPositionClickTriggers || hasTwoFingerClick || hasThreeFingerClick

        setupNSEventMonitors()
        updateMultitouchMonitoringState()
        setupClickSuppressionTap()

        NSLog("[TrackpadMonitor] Registered %d gesture triggers with actions", registeredTriggers.count)
    }

    // MARK: - Multitouch monitoring via private framework

    private var needsMultitouch: Bool {
        LiveTouchState.isVisualizerActive ||
        hasTipTapTriggers ||
        hasTipTapMiddle ||
        hasTapTriggers ||
        has1FingerDrawGestures ||
        hasPositionClickTriggers ||
        hasTwoFingerClick ||
        hasThreeFingerClick ||
        hasPressDragTriggers ||
        hasThreeFingerSwipe ||
        hasFourFingerSwipe
    }

    func updateMultitouchMonitoringState() {
        if needsMultitouch {
            if !multitouchActive {
                setupMultitouchMonitoring()
            }
        } else {
            if multitouchActive {
                stopMultitouchMonitoring()
            }
        }
    }

    private func stopMultitouchMonitoring() {
        guard multitouchActive else { return }
        if let unregister = _MTUnregisterContactFrameCallback,
           let stop = _MTDeviceStop {
            for device in devices {
                unregister(device, touchCallback)
                stop(device)
            }
        }
        devices.removeAll()
        multitouchActive = false
        if sharedTrackpadMonitor === self {
            sharedTrackpadMonitor = nil
        }
        NSLog("[TrackpadMonitor] Multitouch monitoring stopped")
    }

    private func setupMultitouchMonitoring() {
        guard let createList = _MTDeviceCreateList,
              let registerCallback = _MTRegisterContactFrameCallback,
              let startDevice = _MTDeviceStart else {
            NSLog("[TrackpadMonitor] WARNING: MultitouchSupport.framework not available")
            return
        }

        sharedTrackpadMonitor = self

        let cfArray = createList().takeRetainedValue()
        let count = CFArrayGetCount(cfArray)
        NSLog("[TrackpadMonitor] MTDeviceCreateList returned %d devices", count)

        guard count > 0 else {
            NSLog("[TrackpadMonitor] WARNING: No multitouch devices found")
            return
        }

        for i in 0..<count {
            guard let device = CFArrayGetValueAtIndex(cfArray, i) else { continue }
            let deviceRef = UnsafeMutableRawPointer(mutating: device)
            registerCallback(deviceRef, touchCallback)
            startDevice(deviceRef, 0)
            devices.append(deviceRef)
            NSLog("[TrackpadMonitor] Registered callback on device %d", i)
        }
        multitouchActive = true
        NSLog("[TrackpadMonitor] Multitouch monitoring active on %d devices", devices.count)
    }

    // Known field offsets within a single MTTouch struct (stable across macOS versions)
    private static let offsetFingerID: Int = 24
    private static let offsetNormX: Int = 32
    private static let offsetNormY: Int = 36
    private static let offsetMajorAxis: Int = 52

    /// Auto-detect the stride between consecutive MTTouch structs in the raw buffer.
    /// The frame field (Int32 at offset 0) is the same for all touches in a callback.
    private func detectTouchStride(raw: UnsafeMutableRawPointer, numTouches: Int) -> Int {
        let defaultStride = MemoryLayout<MTTouch>.stride // 80 on most builds
        guard numTouches >= 2 else { return defaultStride }

        let frame0 = raw.load(fromByteOffset: 0, as: Int32.self)

        // Try common struct sizes (80 = our struct, then larger variants on newer macOS)
        for candidate in [defaultStride, 84, 88, 92, 96, 104, 112, 120, 128] {
            let frame1 = raw.load(fromByteOffset: candidate, as: Int32.self)
            if frame1 == frame0 {
                // Verify normalizedPosition of second touch is plausible
                let px = raw.load(fromByteOffset: candidate + Self.offsetNormX, as: Float.self)
                let py = raw.load(fromByteOffset: candidate + Self.offsetNormY, as: Float.self)
                if px >= 0 && px <= 1.5 && py >= 0 && py <= 1.5 {
                    NSLog("[TrackpadMonitor] Detected touch struct stride: %d bytes (Swift default: %d)", candidate, defaultStride)
                    return candidate
                }
            }
        }

        NSLog("[TrackpadMonitor] Could not detect stride, using default: %d", defaultStride)
        return defaultStride
    }

    /// Read a single touch's relevant fields from the raw buffer at the given byte offset.
    private func readTouch(from raw: UnsafeMutableRawPointer, at byteOffset: Int) -> (fingerID: Int32, x: Float, y: Float, majorAxis: Float) {
        let fid = raw.load(fromByteOffset: byteOffset + Self.offsetFingerID, as: Int32.self)
        let px  = raw.load(fromByteOffset: byteOffset + Self.offsetNormX, as: Float.self)
        let py  = raw.load(fromByteOffset: byteOffset + Self.offsetNormY, as: Float.self)
        let maj = raw.load(fromByteOffset: byteOffset + Self.offsetMajorAxis, as: Float.self)
        return (fid, px, py, maj)
    }

    func handleMultitouchFrame(rawTouches: UnsafeMutableRawPointer?, numTouches: Int, timestamp: Double) {
        let activeFingersCount = numTouches
        let previousFingers = currentFingers

        // Fast path: if no touches now and no touches previously, and no pending TipTap, do nothing!
        if activeFingersCount == 0 && previousFingers == 0 && !tipTapPending {
            return
        }

        let visualizerActive = LiveTouchState.isVisualizerActive

        // 1. Single finger extraction (only when needed by registered 1-finger recognizers or visualizer)
        var singleFingerX: Float?
        var singleFingerY: Float?
        let needsSingleFinger = activeFingersCount == 1 && rawTouches != nil &&
            (hasTipTapTriggers || hasPositionClickTriggers || has1FingerDrawGestures || visualizerActive)

        if needsSingleFinger, let raw = rawTouches {
            singleFingerX = raw.load(fromByteOffset: Self.offsetNormX, as: Float.self)
            singleFingerY = raw.load(fromByteOffset: Self.offsetNormY, as: Float.self)
        }

        // Position click tracking
        if hasPositionClickTriggers {
            if let sx = singleFingerX, let sy = singleFingerY {
                lastSingleFingerPos = (x: sx, y: sy)
            } else if activeFingersCount != 1 {
                lastSingleFingerPos = nil
            }
        }

        // Visualizer points extraction (ONLY when visualizer is actually on screen!)
        if visualizerActive {
            var liveTouchPoints: [TouchPoint] = []
            if let raw = rawTouches, activeFingersCount > 0 {
                if touchStride == 0 && activeFingersCount >= 2 {
                    touchStride = detectTouchStride(raw: raw, numTouches: activeFingersCount)
                }
                let stride = touchStride > 0 ? touchStride : MemoryLayout<MTTouch>.stride

                liveTouchPoints.reserveCapacity(activeFingersCount)
                for i in 0..<activeFingersCount {
                    let byteOffset = i * stride
                    let px = raw.load(fromByteOffset: byteOffset + Self.offsetNormX, as: Float.self)
                    let py = raw.load(fromByteOffset: byteOffset + Self.offsetNormY, as: Float.self)
                    if px > 0.001 || py > 0.001 {
                        let fid = raw.load(fromByteOffset: byteOffset + Self.offsetFingerID, as: Int32.self)
                        let maj = raw.load(fromByteOffset: byteOffset + Self.offsetMajorAxis, as: Float.self)
                        liveTouchPoints.append(TouchPoint(
                            id: Int(fid),
                            x: px,
                            y: py,
                            size: maj
                        ))
                    }
                }
            }

            let anyButtonDown = NSEvent.pressedMouseButtons != 0
            if !anyButtonDown {
                TrackpadMonitor.pendingSuppressClick = false
            }
            let shouldUpdate: Bool
            if activeFingersCount == 0 {
                shouldUpdate = true
                lastVisualizerUpdateTime = timestamp
            } else if (timestamp - lastVisualizerUpdateTime) >= visualizerMinInterval {
                shouldUpdate = true
                lastVisualizerUpdateTime = timestamp
            } else {
                shouldUpdate = false
            }

            if shouldUpdate {
                LiveTouchState.shared.setPressed(anyButtonDown && !liveTouchPoints.isEmpty)
                LiveTouchState.shared.update(liveTouchPoints)
            }
        } else if previousFingers > 0 && activeFingersCount == 0 {
            TrackpadMonitor.pendingSuppressClick = false
            LiveTouchState.shared.setPressed(false)
            LiveTouchState.shared.update([])
        }

        // Touch session tracking
        if activeFingersCount > 0 && previousFingers == 0 && !tipTapPending {
            touchBegan = Date()
            peakFingers = activeFingersCount
            gestureConsumed = false
            hadOneFingerRest = false
            oneFingerRestX = nil
            oneFingerStartTime = nil
            twoFingerStartTime = nil
        }

        if activeFingersCount > peakFingers {
            peakFingers = activeFingersCount
        }

        currentFingers = activeFingersCount

        // --- TipTap Left/Right detection ---
        if hasTipTapTriggers {
            handleTipTapFrame(activeFingersCount: activeFingersCount, previousFingers: previousFingers, singleFingerX: singleFingerX)
        }

        // --- TipTap Middle detection ---
        if hasTipTapMiddle {
            handleTipTapMiddleFrame(activeFingersCount: activeFingersCount, previousFingers: previousFingers)
        }

        // --- Regular tap detection ---
        if hasTapTriggers && activeFingersCount == 0 && previousFingers > 0 && touchBegan != nil {
            handleTapRelease(previousFingers: previousFingers)
        } else if activeFingersCount == 0 && previousFingers > 0 {
            touchBegan = nil
            peakFingers = 0
        }

        // --- Drawing gesture detection ---
        if has1FingerDrawGestures {
            handleDrawingGesturesFrame(activeFingersCount: activeFingersCount, singleFingerX: singleFingerX, singleFingerY: singleFingerY)
        }
    }

    private func handleTipTapFrame(activeFingersCount: Int, previousFingers: Int, singleFingerX: Float?) {
        // Track 1-finger resting phase
        if activeFingersCount == 1 {
            if oneFingerStartTime == nil {
                oneFingerStartTime = Date()
            }
            if let sx = singleFingerX, sx > 0.01 {
                oneFingerRestX = sx
            }
        }

        // 1→2 transition: second finger just landed
        if activeFingersCount == 2 && previousFingers == 1 {
            twoFingerStartTime = Date()
            let isPressed = NSEvent.pressedMouseButtons & 0x1 != 0
            if let restStart = oneFingerStartTime, isPressed {
                let restDuration = Date().timeIntervalSince(restStart)
                hadOneFingerRest = restDuration >= tipTapMinRestTime
                if hadOneFingerRest {
                    tipTapPending = true
                    tipTapPendingTime = Date()
                }
            } else {
                hadOneFingerRest = false
            }
        }

        // 0→2 transition: both fingers landed at once — NOT a TipTap
        if activeFingersCount == 2 && previousFingers == 0 {
            hadOneFingerRest = false
            tipTapPending = false
            twoFingerStartTime = Date()
        }

        // 2→1 transition: clean TipTap
        if activeFingersCount == 1 && previousFingers == 2 && tipTapPending {
            if let restX = oneFingerRestX, let remainingX = singleFingerX {
                let sameSide = (restX < 0.50 && remainingX < 0.50) || (restX >= 0.50 && remainingX >= 0.50)
                if sameSide {
                    checkAndFireTipTap()
                } else {
                    tipTapPending = false
                    oneFingerRestX = remainingX
                    oneFingerStartTime = Date()
                }
            } else {
                checkAndFireTipTap()
            }
        }

        // 0→1 after a pending TipTap (2→0→1 sequence): fire it!
        if activeFingersCount == 1 && previousFingers == 0 && tipTapPending {
            checkAndFireTipTap()
        }

        // Timeout
        if tipTapPending, let pt = tipTapPendingTime, Date().timeIntervalSince(pt) > tipTapMaxTapDuration {
            tipTapPending = false
        }

        // Reset if we go above 2 fingers
        if activeFingersCount > 2 {
            hadOneFingerRest = false
            tipTapPending = false
            oneFingerRestX = nil
            oneFingerStartTime = nil
        }
    }

    private func handleTipTapMiddleFrame(activeFingersCount: Int, previousFingers: Int) {
        if activeFingersCount == 2 {
            if twoFingerRestTime == nil {
                twoFingerRestTime = Date()
            }
        }

        if activeFingersCount == 3 && previousFingers == 2 {
            threeFingerStartTime = Date()
            if let restStart = twoFingerRestTime, Date().timeIntervalSince(restStart) >= tipTapMinRestTime {
                tipTapMiddlePending = true
            }
        }

        if activeFingersCount == 2 && previousFingers == 3 && tipTapMiddlePending {
            if let threeStart = threeFingerStartTime, Date().timeIntervalSince(threeStart) < tipTapMaxTapDuration {
                tipTapMiddlePending = false
                gestureConsumed = true
                DispatchQueue.main.async { [self] in
                    GestureLog.shared.logFromAnyThread("TipTap: TipTap Middle", level: .detect)
                    fireGesture(.tipTapMiddle)
                }
            } else {
                tipTapMiddlePending = false
            }
        }

        if activeFingersCount == 0 || activeFingersCount == 1 {
            twoFingerRestTime = nil
            tipTapMiddlePending = false
            threeFingerStartTime = nil
        }
        if activeFingersCount > 3 {
            tipTapMiddlePending = false
        }
    }

    private func handleTapRelease(previousFingers: Int) {
        guard let began = touchBegan else {
            peakFingers = 0
            return
        }
        let elapsed = Date().timeIntervalSince(began)
        touchBegan = nil
        let peak = peakFingers
        peakFingers = 0

        guard elapsed < tapTimeout && !gestureConsumed else { return }

        if peak == 2 {
            if hasTwoFingerDoubleTap {
                let now = Date()
                if let lastTap = lastTwoFingerTapTime, now.timeIntervalSince(lastTap) < doubleTapWindow {
                    doubleTapTimer?.cancel()
                    doubleTapTimer = nil
                    lastTwoFingerTapTime = nil
                    NSLog("[TrackpadMonitor] Detected 2-finger double tap")
                    DispatchQueue.main.async { [self] in
                        GestureLog.shared.logFromAnyThread("Detected 2-finger double tap", level: .detect)
                        fireGesture(.twoFingerDoubleTap)
                    }
                } else {
                    lastTwoFingerTapTime = now
                    if hasTwoFingerTap {
                        let timer = DispatchWorkItem { [weak self] in
                            guard let self = self else { return }
                            self.lastTwoFingerTapTime = nil
                            NSLog("[TrackpadMonitor] Detected 2-finger tap (duration: %.2fs)", elapsed)
                            DispatchQueue.main.async {
                                GestureLog.shared.logFromAnyThread("Detected 2-finger tap (\(String(format: "%.2fs", elapsed)))", level: .detect)
                                self.fireGesture(.twoFingerTap)
                            }
                        }
                        doubleTapTimer = timer
                        DispatchQueue.global().asyncAfter(deadline: .now() + doubleTapWindow, execute: timer)
                    }
                }
            } else if hasTwoFingerTap {
                NSLog("[TrackpadMonitor] Detected 2-finger tap (duration: %.2fs)", elapsed)
                DispatchQueue.main.async { [self] in
                    GestureLog.shared.logFromAnyThread("Detected 2-finger tap (\(String(format: "%.2fs", elapsed)))", level: .detect)
                    fireGesture(.twoFingerTap)
                }
            }
        } else if peak == 3 && hasThreeFingerTap {
            NSLog("[TrackpadMonitor] Detected 3-finger tap (duration: %.2fs)", elapsed)
            DispatchQueue.main.async { [self] in
                GestureLog.shared.logFromAnyThread("Detected 3-finger tap (\(String(format: "%.2fs", elapsed)))", level: .detect)
                fireGesture(.threeFingerTap)
            }
        } else if peak == 4 && hasFourFingerTap {
            NSLog("[TrackpadMonitor] Detected 4-finger tap (duration: %.2fs)", elapsed)
            DispatchQueue.main.async { [self] in
                GestureLog.shared.logFromAnyThread("Detected 4-finger tap (\(String(format: "%.2fs", elapsed)))", level: .detect)
                fireGesture(.fourFingerTap)
            }
        } else if peak == 5 && hasFiveFingerTap {
            NSLog("[TrackpadMonitor] Detected 5-finger tap (duration: %.2fs)", elapsed)
            DispatchQueue.main.async { [self] in
                GestureLog.shared.logFromAnyThread("Detected 5-finger tap (\(String(format: "%.2fs", elapsed)))", level: .detect)
                fireGesture(.fiveFingerTap)
            }
        }
    }

    private func handleDrawingGesturesFrame(activeFingersCount: Int, singleFingerX: Float?, singleFingerY: Float?) {
        if activeFingersCount == 1, let x = singleFingerX, let y = singleFingerY {
            let isClickedNow = NSEvent.pressedMouseButtons & 0x1 != 0
            if x > 0.01 && y > 0.01 && isClickedNow {
                if hasCircleTriggers { trackCirclePoint(x: x, y: y) }
                if hasTriangleTriggers { trackTrianglePoint(x: x, y: y) }
                if hasEdgeSlideTriggers { trackEdgeDrag(x: x, y: y) }
                return
            }
        }

        if !circlePoints.isEmpty || !trianglePoints.isEmpty || edgeSlideLastY != nil || circleDrawingActive {
            resetCircleState()
            resetTriangleState()
            resetEdgeDragState()
            stopSuppressingMouse()
        }
    }

    // MARK: - Circle gesture helpers

    private func trackCirclePoint(x: Float, y: Float) {
        circlePoints.append((x: x, y: y))
        circleSumX += x
        circleSumY += y

        // Update running centroid in O(1)
        let n = Float(circlePoints.count)
        circleCenterX = circleSumX / n
        circleCenterY = circleSumY / n

        // Calculate angle from centroid to current point
        let dx = x - circleCenterX
        let dy = y - circleCenterY

        // Need minimum distance from center to avoid noise at center
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0.01 else { return }

        let angle = atan2(dy, dx)

        if let lastAngle = circleLastAngle {
            var delta = angle - lastAngle
            // Normalize to [-π, π]
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            circleCumulativeAngle += delta
        }
        circleLastAngle = angle

        // Check if we have enough points to validate circularity
        if circlePoints.count >= circleMinPoints {
            // Validate circularity: check that points are roughly equidistant from centroid
            if !isPathCircular() {
                // Not circular — trim old points to keep tracking fresh
                if circlePoints.count > 40 {
                    circlePoints.removeFirst(circlePoints.count - 30)
                    circleSumX = circlePoints.reduce(0) { $0 + $1.x }
                    circleSumY = circlePoints.reduce(0) { $0 + $1.y }
                    circleCumulativeAngle = 0
                    circleLastFiredAngle = 0
                    circleFireCount = 0
                    circleStartTime = nil
                    circleLastAngle = angle
                    stopSuppressingMouse(for: .circle)
                }
                return
            }

            // Progressive firing: fire every N degrees of rotation, accelerating over time.
            if circleStartTime == nil {
                circleStartTime = Date()
                startSuppressingMouse(for: .circle)
            }

            let elapsed = Date().timeIntervalSince(circleStartTime ?? Date())
            // Acceleration: angle threshold decreases with time
            // Starts at π/2 (~90°), decreases to π/6 (~30°) over ~2 seconds
            let accelerationFactor = min(1.0, elapsed / 2.0)
            let baseAngle: Float = .pi / 2
            let minAngle: Float = .pi / 6
            let fireAngleThreshold = baseAngle - (baseAngle - minAngle) * Float(accelerationFactor)

            let absCumulative = abs(circleCumulativeAngle)

            // Require at least half a circle before first fire to avoid false positives
            if circleFireCount == 0 && absCumulative < .pi { return }

            let angleSinceLastFire = absCumulative - abs(circleLastFiredAngle)

            if angleSinceLastFire >= fireAngleThreshold {
                circleLastFiredAngle = circleCumulativeAngle
                circleFireCount += 1
                resetTriangleState()  // suppress triangle since circle won

                if circleCumulativeAngle > 0 {
                    if hasCircleCounterClockwise {
                        DispatchQueue.main.async { [self] in
                            GestureLog.shared.logFromAnyThread("Circle: Counter-Clockwise (#\(circleFireCount))", level: .detect)
                            fireGesture(.circleCounterClockwise)
                        }
                    }
                } else {
                    if hasCircleClockwise {
                        DispatchQueue.main.async { [self] in
                            GestureLog.shared.logFromAnyThread("Circle: Clockwise (#\(circleFireCount))", level: .detect)
                            fireGesture(.circleClockwise)
                        }
                    }
                }
            }
        }
    }

    /// Check if the tracked path is roughly circular (not a line or zigzag)
    private func isPathCircular() -> Bool {
        guard circlePoints.count >= circleMinPoints else { return false }

        var sumDist: Float = 0
        var sumDistSq: Float = 0
        let count = Float(circlePoints.count)

        for p in circlePoints {
            let dx = p.x - circleCenterX
            let dy = p.y - circleCenterY
            let d = sqrt(dx * dx + dy * dy)
            sumDist += d
            sumDistSq += d * d
        }

        let meanDist = sumDist / count
        guard meanDist > 0.02 && meanDist < 0.09 else { return false }

        let variance = max(0, (sumDistSq / count) - (meanDist * meanDist))
        let stdDev = sqrt(variance)
        let cv = stdDev / meanDist

        return cv < 0.45
    }

    private func resetCircleState() {
        circlePoints.removeAll()
        circleSumX = 0
        circleSumY = 0
        circleCumulativeAngle = 0
        circleLastAngle = nil
        circleCenterX = 0
        circleCenterY = 0
        circleLastFiredAngle = 0
        circleStartTime = nil
        circleFireCount = 0
        stopSuppressingMouse(for: .circle)
    }

    private func startSuppressingMouse(for reason: MouseSuppressionReason) {
        let suppress = UserDefaults.standard.object(forKey: "GTTSuppressMouseDuringDrawing") as? Bool ?? true
        guard suppress else { return }

        mouseSuppressionReason = reason
        guard !circleDrawingActive else { return }
        circleDrawingActive = true

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.circleDrawingActive, self.mouseEventTap == nil else { return }

            let eventMask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue)
                | (1 << CGEventType.leftMouseDragged.rawValue)
                | (1 << CGEventType.rightMouseDragged.rawValue)

            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { _, _, event, _ in
                    // Suppress the event by returning nil
                    return nil
                },
                userInfo: nil
            ) else { return }

            self.mouseEventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.mouseEventTapRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func stopSuppressingMouse(for reason: MouseSuppressionReason? = nil) {
        if let reason = reason, mouseSuppressionReason != reason {
            return
        }
        mouseSuppressionReason = .none
        guard circleDrawingActive else { return }
        circleDrawingActive = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let tap = self.mouseEventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
                if let source = self.mouseEventTapRunLoopSource {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                }
                self.mouseEventTap = nil
                self.mouseEventTapRunLoopSource = nil
            }
        }
    }

    // MARK: - Triangle gesture helpers

    private func trackTrianglePoint(x: Float, y: Float) {
        trianglePoints.append((x: x, y: y))
        // Don't check triangle if circle already fired this session, or triangle already fired
        guard !triangleFired, circleFireCount == 0, trianglePoints.count >= 20 else { return }
        if isTriangle() {
            triangleFired = true
            resetCircleState()  // suppress circle since triangle won
            DispatchQueue.main.async { [self] in
                GestureLog.shared.logFromAnyThread("Drawing: Triangle detected", level: .detect)
                fireGesture(.drawTriangle)
            }
        }
    }

    /// Detect if the drawn path forms a triangle:
    /// 1. Simplify the path using Ramer-Douglas-Peucker
    /// 2. Check if simplified path has ~3 corners
    /// 3. Verify the path is roughly closed
    private func isTriangle() -> Bool {
        let pts = trianglePoints
        guard pts.count >= 20 else { return false }

        // Path must span a minimum area (not just jitter)
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let span = max(maxX - minX, maxY - minY)
        guard span > 0.08 else { return false }

        // Reject if path looks circular (let circle detector handle it)
        if isPathCircular() { return false }

        // Check path is roughly closed (end near start)
        let startX = pts.first!.x, startY = pts.first!.y
        let endX = pts.last!.x, endY = pts.last!.y
        let closeDist = sqrt((endX - startX) * (endX - startX) + (endY - startY) * (endY - startY))
        guard closeDist < span * 0.4 else { return false }

        // Simplify path with RDP algorithm
        let simplified = rdpSimplify(pts, epsilon: span * 0.08)
        // A triangle simplifies to 3-5 points (3 corners + closure)
        // Remove last point if it's close to first (closure duplicate)
        var corners = simplified
        if corners.count >= 3 {
            let last = corners.last!, first = corners.first!
            let d = sqrt((last.x - first.x) * (last.x - first.x) + (last.y - first.y) * (last.y - first.y))
            if d < span * 0.15 {
                corners.removeLast()
            }
        }

        // Should have exactly 3 corners
        guard corners.count == 3 else { return false }

        // Verify angles at each corner are reasonable for a triangle (30°–150°)
        for i in 0..<3 {
            let a = corners[i]
            let b = corners[(i + 1) % 3]
            let c = corners[(i + 2) % 3]
            let angle = angleBetween(a: a, vertex: b, c: c)
            if angle < 0.5 || angle > 2.6 { return false } // ~30° to ~150°
        }

        return true
    }

    /// Ramer-Douglas-Peucker line simplification
    private func rdpSimplify(_ points: [(x: Float, y: Float)], epsilon: Float) -> [(x: Float, y: Float)] {
        guard points.count > 2 else { return points }

        // Find the point with maximum distance from the line between first and last
        let first = points.first!, last = points.last!
        var maxDist: Float = 0
        var maxIdx = 0
        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(point: points[i], lineStart: first, lineEnd: last)
            if d > maxDist {
                maxDist = d
                maxIdx = i
            }
        }

        if maxDist > epsilon {
            let left = rdpSimplify(Array(points[0...maxIdx]), epsilon: epsilon)
            let right = rdpSimplify(Array(points[maxIdx...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [first, last]
        }
    }

    private func perpendicularDistance(point: (x: Float, y: Float), lineStart: (x: Float, y: Float), lineEnd: (x: Float, y: Float)) -> Float {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0.0001 else {
            return sqrt((point.x - lineStart.x) * (point.x - lineStart.x) + (point.y - lineStart.y) * (point.y - lineStart.y))
        }
        return abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x) / len
    }

    private func angleBetween(a: (x: Float, y: Float), vertex: (x: Float, y: Float), c: (x: Float, y: Float)) -> Float {
        let v1x = a.x - vertex.x, v1y = a.y - vertex.y
        let v2x = c.x - vertex.x, v2y = c.y - vertex.y
        let dot = v1x * v2x + v1y * v2y
        let cross = v1x * v2y - v1y * v2x
        return abs(atan2(cross, dot))
    }

    private func resetTriangleState() {
        trianglePoints.removeAll()
        triangleFired = false
    }

    // MARK: - Edge drag detection

    private func trackEdgeDrag(x: Float, y: Float) {
        // Determine if finger is on an edge
        let onLeft = x < edgeSlideZoneWidth
        let onRight = x > (1.0 - edgeSlideZoneWidth)

        guard onLeft || onRight else {
            resetEdgeDragState()
            return
        }

        let side: EdgeSide = onLeft ? .left : .right

        guard let lastY = edgeSlideLastY, edgeSlideEdge == side else {
            // Anchor point established on the edge
            edgeSlideLastY = y
            edgeSlideEdge = side
            return
        }

        let deltaY = y - lastY
        if abs(deltaY) >= edgeSlideStep {
            // Actively sliding along the edge — suppress mouse while sliding
            startSuppressingMouse(for: .edgeSlide)
            // Fire once per step, then advance the anchor
            let gesture: TrackpadGesture
            switch (side, deltaY > 0) {
            case (.left, true):   gesture = .leftEdgeSlideUp
            case (.left, false):  gesture = .leftEdgeSlideDown
            case (.right, true):  gesture = .rightEdgeSlideUp
            case (.right, false): gesture = .rightEdgeSlideDown
            }
            edgeSlideLastY = y
            if registeredTriggers.contains(where: { $0.gesture == gesture }) {
                DispatchQueue.main.async { [self] in
                    fireGesture(gesture)
                }
            }
        }
    }

    private func resetEdgeDragState() {
        edgeSlideLastY = nil
        edgeSlideEdge = nil
        stopSuppressingMouse(for: .edgeSlide)
    }

    // MARK: - Position click detection

    private func handlePositionClick() {
        guard hasPositionClickTriggers, !positionClickFired, currentFingers == 1,
              let pos = lastSingleFingerPos else { return }

        let x = pos.x
        let y = pos.y

        // Zone layout (normalized 0-1, origin bottom-left):
        // Corners: small zones at the very tips of the trackpad
        // Middle top/bottom: wider strip spanning more of the center edge
        let cornerW: Float = 0.12
        let cornerH: Float = 0.12
        let middleH: Float = 0.20   // middle strips extend further in than corners

        let gesture: TrackpadGesture?
        if x < cornerW && y > (1 - cornerH) {
            gesture = .cornerClickTopLeft
        } else if x > (1 - cornerW) && y > (1 - cornerH) {
            gesture = .cornerClickTopRight
        } else if x < cornerW && y < cornerH {
            gesture = .cornerClickBottomLeft
        } else if x > (1 - cornerW) && y < cornerH {
            gesture = .cornerClickBottomRight
        } else if y > (1 - middleH) {
            gesture = .middleClickTop
        } else if y < middleH {
            gesture = .middleClickBottom
        } else {
            gesture = nil
        }

        if let gesture = gesture, registeredTriggers.contains(where: { $0.gesture == gesture }) {
            positionClickFired = true
            DispatchQueue.main.async { [self] in
                GestureLog.shared.logFromAnyThread("Position Click: \(gesture.rawValue) (x=\(String(format: "%.2f", x)), y=\(String(format: "%.2f", y)))", level: .detect)
                fireGesture(gesture)
            }
        }
    }

    private func checkAndFireTipTap() {
        guard hasTipTapTriggers,
              let twoStart = twoFingerStartTime,
              let restX = oneFingerRestX else {
            // TipTap rejected: missing state
            tipTapPending = false
            return
        }

        // Cooldown: prevent false fires when switching resting finger sides
        if let lastFire = lastTipTapFiredTime, Date().timeIntervalSince(lastFire) < tipTapCooldown {
            tipTapPending = false
            return
        }

        // The two-finger phase must be brief (the tap was quick)
        let tapDuration = Date().timeIntervalSince(twoStart)
        guard tapDuration < tipTapMaxTapDuration else {
            // TipTap rejected: tap too long
            tipTapPending = false
            return
        }

        // Determine direction from resting finger X position:
        // Rester on left → tapper was on right → TipTap Right
        // Rester on right → tapper was on left → TipTap Left
        // (TipTap Middle is a different gesture: 2 fingers rest + tap between)
        let gesture: TrackpadGesture
        if restX < 0.50 {
            gesture = .tipTapRight
        } else {
            gesture = .tipTapLeft
        }

        gestureConsumed = true
        tipTapPending = false
        hadOneFingerRest = false
        lastTipTapFiredTime = Date()
        // Reset rest tracking so switching sides requires the finger to settle again
        oneFingerStartTime = Date()

        guard registeredTriggers.contains(where: { $0.gesture == gesture }) else {
            return
        }

        DispatchQueue.main.async { [self] in
            GestureLog.shared.logFromAnyThread("TipTap: \(gesture.rawValue) (restX=\(String(format: "%.2f", restX)))", level: .detect)
            fireGesture(gesture)
        }
    }

    // MARK: - NSEvent monitors for scroll/pinch/rotate

    private func setupNSEventMonitors() {
        let scrollHandler: (NSEvent) -> Void = { [weak self] e in self?.handleScroll(e) }
        let magnifyHandler: (NSEvent) -> Void = { [weak self] e in self?.handleMagnify(e) }
        let rotateHandler: (NSEvent) -> Void = { [weak self] e in self?.handleRotate(e) }
        let dragHandler: (NSEvent) -> Void = { [weak self] e in self?.handleDrag(e) }

        // Left-click press: used for gesture logic (circle, position click)
        // Visual press state is handled in the multitouch callback via NSEvent.pressedMouseButtons
        let leftPressHandler: (NSEvent) -> Void = { [weak self] _ in
            guard let self = self else { return }
            self.trackpadIsPressed = true
            if self.hasPressDragTriggers && self.currentFingers >= 2 {
                self.pressDragDeltaX = 0
                self.pressDragActive = true
            }
            if self.hasPositionClickTriggers {
                self.handlePositionClick()
            }
        }
        let leftReleaseHandler: (NSEvent) -> Void = { [weak self] _ in
            guard let self = self else { return }
            if self.hasPressDragTriggers {
                self.handlePressDragEnd()
            }
            self.trackpadIsPressed = false
            self.positionClickFired = false
            TrackpadMonitor.pendingSuppressClick = false
            if self.has1FingerDrawGestures {
                if !self.circlePoints.isEmpty || !self.trianglePoints.isEmpty || self.edgeSlideLastY != nil || self.circleDrawingActive {
                    self.resetCircleState()
                    self.resetTriangleState()
                    self.resetEdgeDragState()
                    self.stopSuppressingMouse()
                }
            }
        }

        if hasSwipeTriggers {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: scrollHandler) {
                monitors.append(m)
            }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { e in scrollHandler(e); return e }) {
                monitors.append(m)
            }
        }
        if hasPinchTriggers {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .magnify, handler: magnifyHandler) {
                monitors.append(m)
            }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .magnify, handler: { e in magnifyHandler(e); return e }) {
                monitors.append(m)
            }
        }
        if hasRotateTriggers {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .rotate, handler: rotateHandler) {
                monitors.append(m)
            }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .rotate, handler: { e in rotateHandler(e); return e }) {
                monitors.append(m)
            }
        }
        let needsMouseClicks = hasPressDragTriggers || hasClickTriggers || has1FingerDrawGestures
        if needsMouseClicks {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: leftPressHandler) {
                monitors.append(m)
            }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { e in leftPressHandler(e); return e }) {
                monitors.append(m)
            }
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: leftReleaseHandler) {
                monitors.append(m)
            }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { e in leftReleaseHandler(e); return e }) {
                monitors.append(m)
            }
        }
        if hasPressDragTriggers {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: dragHandler) {
                monitors.append(m)
            }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged, handler: { e in dragHandler(e); return e }) {
                monitors.append(m)
            }
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDragged, handler: dragHandler) {
                monitors.append(m)
            }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDragged, handler: { e in dragHandler(e); return e }) {
                monitors.append(m)
            }
        }
        if hasTwoFingerClick {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown, handler: leftPressHandler) {
                monitors.append(m)
            }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown, handler: { e in leftPressHandler(e); return e }) {
                monitors.append(m)
            }
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseUp, handler: leftReleaseHandler) {
                monitors.append(m)
            }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp, handler: { e in leftReleaseHandler(e); return e }) {
                monitors.append(m)
            }
        }
    }

    // MARK: - Press-drag handling

    private func handleDrag(_ event: NSEvent) {
        guard currentFingers == 2 else { return }
        pressDragDeltaX += event.deltaX
    }

    private func handlePressDragEnd() {
        guard pressDragActive && currentFingers == 2 else {
            pressDragDeltaX = 0; pressDragActive = false; return
        }
        let stored = UserDefaults.standard.double(forKey: "GTTPressDragThreshold")
        let threshold: CGFloat = stored > 0 ? CGFloat(stored) : 300
        if abs(pressDragDeltaX) > threshold {
            let gesture: TrackpadGesture = pressDragDeltaX > 0 ? .twoFingerPressDragRight : .twoFingerPressDragLeft
            if registeredTriggers.contains(where: { $0.gesture == gesture }) {
                fireGesture(gesture)
            }
        }
        pressDragDeltaX = 0; pressDragActive = false
    }

    // MARK: - Scroll / Swipe handling

    private func handleScroll(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }

        if event.phase == .began || event.phase == .mayBegin {
            scrollDeltaX = 0; scrollDeltaY = 0
            scrollStartTime = Date()
            // Use multitouch finger count (reliable) instead of event.touches() (empty for global monitors)
            scrollFingerCount = max(currentFingers, 2)
        }

        // Update finger count from multitouch if we missed .began
        if scrollFingerCount == 0 {
            scrollFingerCount = max(currentFingers, 2)
        }

        let fingers = scrollFingerCount
        let isConfiguredForFingers = (fingers == 2 && hasTwoFingerSwipe) ||
                                     (fingers == 3 && hasThreeFingerSwipe) ||
                                     (fingers == 4 && hasFourFingerSwipe)

        guard isConfiguredForFingers else {
            if event.phase == .ended || event.phase == .cancelled {
                scrollDeltaX = 0; scrollDeltaY = 0; scrollFingerCount = 0; scrollStartTime = nil
            }
            return
        }

        if scrollStartTime == nil {
            scrollStartTime = Date()
        }

        scrollDeltaX += event.scrollingDeltaX
        scrollDeltaY += event.scrollingDeltaY

        // Only consume gesture after meaningful scroll movement (preserves taps)
        if abs(scrollDeltaX) > 10 || abs(scrollDeltaY) > 10 {
            gestureConsumed = true
        }

        if event.phase == .ended || event.phase == .cancelled {
            let absX = abs(scrollDeltaX); let absY = abs(scrollDeltaY)
            let duration = Date().timeIntervalSince(scrollStartTime ?? Date())
            let maxDelta = max(absX, absY)
            let velocity = duration > 0 ? maxDelta / CGFloat(duration) : 0

            guard maxDelta > swipeThreshold else {
                scrollDeltaX = 0; scrollDeltaY = 0; scrollFingerCount = 0; scrollStartTime = nil; return
            }
            let gesture: TrackpadGesture?
            if absX > absY {
                gesture = swipeGesture(fingers: scrollFingerCount, direction: scrollDeltaX > 0 ? .left : .right)
            } else {
                gesture = swipeGesture(fingers: scrollFingerCount, direction: scrollDeltaY > 0 ? .up : .down)
            }
            if let gesture = gesture, registeredTriggers.contains(where: { $0.gesture == gesture }) {
                let minVelocity = swipeMinVelocity(for: gesture)
                if velocity >= minVelocity {
                    GestureLog.shared.logFromAnyThread("Swipe velocity: \(Int(velocity)) pts/sec (min: \(Int(minVelocity)))", level: .detect)
                    fireGesture(gesture)
                }
            }
            scrollDeltaX = 0; scrollDeltaY = 0; scrollFingerCount = 0; scrollStartTime = nil
        }
    }

    private enum SwipeDirection { case up, down, left, right }

    private func swipeGesture(fingers: Int, direction: SwipeDirection) -> TrackpadGesture? {
        switch (fingers, direction) {
        case (2, .up): return .twoFingerSwipeUp
        case (2, .down): return .twoFingerSwipeDown
        case (2, .left): return .twoFingerSwipeLeft
        case (2, .right): return .twoFingerSwipeRight
        case (3, .up): return .threeFingerSwipeUp
        case (3, .down): return .threeFingerSwipeDown
        case (3, .left): return .threeFingerSwipeLeft
        case (3, .right): return .threeFingerSwipeRight
        case (4, .up): return .fourFingerSwipeUp
        case (4, .down): return .fourFingerSwipeDown
        case (4, .left): return .fourFingerSwipeLeft
        case (4, .right): return .fourFingerSwipeRight
        default: return nil
        }
    }

    // MARK: - Magnify

    private func handleMagnify(_ event: NSEvent) {
        if event.phase == .began { magnification = 0 }
        magnification += event.magnification
        if abs(magnification) > 0.02 { gestureConsumed = true }
        if event.phase == .ended || event.phase == .cancelled {
            if magnification > 0.1 && registeredTriggers.contains(where: { $0.gesture == .twoFingerPinchOut }) {
                fireGesture(.twoFingerPinchOut)
            } else if magnification < -0.1 && registeredTriggers.contains(where: { $0.gesture == .twoFingerPinchIn }) {
                fireGesture(.twoFingerPinchIn)
            }
            magnification = 0
        }
    }

    // MARK: - Rotate

    private func handleRotate(_ event: NSEvent) {
        if event.phase == .began { rotation = 0 }
        rotation += CGFloat(event.rotation)
        if abs(rotation) > 1 { gestureConsumed = true }
        if event.phase == .ended || event.phase == .cancelled {
            if rotation > 5 && registeredTriggers.contains(where: { $0.gesture == .twoFingerRotateRight }) {
                fireGesture(.twoFingerRotateRight)
            } else if rotation < -5 && registeredTriggers.contains(where: { $0.gesture == .twoFingerRotateLeft }) {
                fireGesture(.twoFingerRotateLeft)
            }
            rotation = 0
        }
    }

    // MARK: - Click Suppression CGEventTap

    private func setupClickSuppressionTap() {
        let suppressCount = registeredTriggers.filter({ $0.suppressClick }).count
        guard suppressCount > 0 else { return }

        TrackpadMonitor.activeTrackpadMonitor = self

        let eventMask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << 29) /* NSEvent.EventType.pressure */

        let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let monitor = TrackpadMonitor.activeTrackpadMonitor else {
                return Unmanaged.passRetained(event)
            }

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.clickSuppressEventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            // Skip events posted by our own ActionExecutor
            if event.getIntegerValueField(.eventSourceUserData) == 0x475454 {
                return Unmanaged.passRetained(event)
            }

            // While suppressing, swallow all related events until mouseUp
            if TrackpadMonitor.pendingSuppressClick {
                if type == .leftMouseUp {
                    TrackpadMonitor.pendingSuppressClick = false
                }
                return nil // swallow up, drag, and pressure events during suppression
            }

            // On mouseDown, check if a click-based gesture with suppressClick will fire
            if type == .leftMouseDown {
                if let gesture = monitor.clickGestureToSuppress() {
                    TrackpadMonitor.pendingSuppressClick = true
                    DispatchQueue.main.async {
                        monitor.fireGesture(gesture)
                    }
                    return nil // swallow
                }
            }

            return Unmanaged.passRetained(event)
        }

        clickSuppressEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        )

        if let tap = clickSuppressEventTap {
            clickSuppressRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = clickSuppressRunLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            NSLog("[TrackpadMonitor] Failed to create click suppression CGEventTap — Accessibility permission required")
        }
    }

    /// Returns the click gesture to suppress if the current trackpad state matches a registered
    /// click gesture that has suppressClick enabled, or nil if no suppression should happen.
    private func clickGestureToSuppress() -> TrackpadGesture? {
        let globalEnabled = UserDefaults.standard.object(forKey: "GTTGlobalEnabled") as? Bool ?? true
        guard globalEnabled else { return nil }

        // Determine which gesture would fire based on finger count and position
        let gesture: TrackpadGesture?
        if currentFingers == 1, let pos = lastSingleFingerPos {
            let x = pos.x
            let y = pos.y
            let cornerW: Float = 0.12
            let cornerH: Float = 0.12
            let middleH: Float = 0.20

            if x < cornerW && y > (1 - cornerH) {
                gesture = .cornerClickTopLeft
            } else if x > (1 - cornerW) && y > (1 - cornerH) {
                gesture = .cornerClickTopRight
            } else if x < cornerW && y < cornerH {
                gesture = .cornerClickBottomLeft
            } else if x > (1 - cornerW) && y < cornerH {
                gesture = .cornerClickBottomRight
            } else if y > (1 - middleH) {
                gesture = .middleClickTop
            } else if y < middleH {
                gesture = .middleClickBottom
            } else {
                gesture = nil
            }
        } else if currentFingers == 2 {
            gesture = .twoFingerClick
        } else if currentFingers == 3 {
            gesture = .threeFingerClick
        } else {
            gesture = nil
        }

        guard let gesture = gesture else { return nil }

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let matching = registeredTriggers.filter { $0.gesture == gesture && $0.suppressClick }
        let appSpecific = matching.filter { $0.appBundleID != nil && $0.appBundleID == frontBundleID }
        let global = matching.filter { $0.appBundleID == nil }
        let toSuppress = appSpecific.isEmpty ? global : appSpecific

        return toSuppress.isEmpty ? nil : gesture
    }

    private func tearDownClickSuppressionTap() {
        if let tap = clickSuppressEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            clickSuppressEventTap = nil
        }
        if let source = clickSuppressRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            clickSuppressRunLoopSource = nil
        }
        if TrackpadMonitor.activeTrackpadMonitor === self {
            TrackpadMonitor.activeTrackpadMonitor = nil
        }
        TrackpadMonitor.pendingSuppressClick = false
    }

    // MARK: - Fire

    private func fireGesture(_ gesture: TrackpadGesture) {
        // Get the frontmost app's bundle ID
        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Find matching triggers, split into app-specific and global
        let matching = registeredTriggers.filter { $0.gesture == gesture }
        let appSpecific = matching.filter { $0.appBundleID != nil && $0.appBundleID == frontBundleID }
        let global = matching.filter { $0.appBundleID == nil }

        // App-specific triggers take priority — if any exist for this app, skip globals
        let toFire = appSpecific.isEmpty ? global : appSpecific

        guard !toFire.isEmpty else {
            GestureLog.shared.logFromAnyThread("Gesture \(gesture.rawValue) — no matching trigger", level: .noMatch)
            return
        }

        NSLog("[TrackpadMonitor] Detected gesture: %@", gesture.rawValue)

        // Record detected gesture for statistics only when it matches an active trigger
        GestureStatistics.shared.recordDetectionFromAnyThread(gesture.rawValue)

        // Check global toggle — detect but don't fire when disabled
        let globalEnabled = UserDefaults.standard.object(forKey: "GTTGlobalEnabled") as? Bool ?? true
        guard globalEnabled else {
            GestureLog.shared.logFromAnyThread("Gesture \(gesture.rawValue) — paused", level: .noMatch)
            return
        }

        for trigger in toFire {
            let actionNames = trigger.actions.map { $0.actionType.rawValue }.joined(separator: ", ")
            let scope = trigger.appBundleID != nil ? "app-specific" : "global"
            GestureLog.shared.logFromAnyThread("Fired: \(gesture.rawValue) → \(actionNames) (\(scope))", level: .fire)
            GestureStatistics.shared.recordFireFromAnyThread(gesture.rawValue)
            ActionExecutor.executeActions(trigger.actions)
            LiveTouchState.shared.flashTrigger(trigger.id)
            NotificationCenter.default.post(name: .gestureDidFire, object: nil, userInfo: ["name": gesture.rawValue])
        }
    }

    /// Test-only: directly fire a gesture through the normal pipeline
    func fireGestureForTest(_ gesture: TrackpadGesture) {
        fireGesture(gesture)
    }

    func unregisterAll() {
        tearDownClickSuppressionTap()
        stopSuppressingMouse()
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        registeredTriggers.removeAll()

        hasCircleClockwise = false
        hasCircleCounterClockwise = false
        hasCircleTriggers = false
        hasTriangleTriggers = false
        hasEdgeSlideTriggers = false
        has1FingerDrawGestures = false
        hasTwoFingerSwipe = false
        hasThreeFingerSwipe = false
        hasFourFingerSwipe = false
        hasSwipeTriggers = false
        hasPinchTriggers = false
        hasRotateTriggers = false
        hasPressDragTriggers = false
        hasTipTapLeft = false
        hasTipTapRight = false
        hasTipTapTriggers = false
        hasTipTapMiddle = false
        hasTwoFingerTap = false
        hasTwoFingerDoubleTap = false
        hasThreeFingerTap = false
        hasFourFingerTap = false
        hasFiveFingerTap = false
        hasTapTriggers = false
        hasPositionClickTriggers = false
        hasTwoFingerClick = false
        hasThreeFingerClick = false
        hasClickTriggers = false

        trackpadIsPressed = false
        TrackpadMonitor.pendingSuppressClick = false

        doubleTapTimer?.cancel()
        doubleTapTimer = nil
        lastTwoFingerTapTime = nil
        touchBegan = nil
        peakFingers = 0
        currentFingers = 0
        tipTapPending = false
        tipTapMiddlePending = false
        oneFingerStartTime = nil
        twoFingerStartTime = nil
        twoFingerRestTime = nil
        threeFingerStartTime = nil
        lastSingleFingerPos = nil
        positionClickFired = false

        stopMultitouchMonitoring()
    }

    deinit {
        if let obs = visualizerObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        unregisterAll()
    }
}
