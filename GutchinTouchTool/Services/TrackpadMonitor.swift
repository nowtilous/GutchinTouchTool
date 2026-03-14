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
    private var registeredTriggers: [(id: UUID, gesture: TrackpadGesture, actions: [TriggerAction], appBundleID: String?)] = []
    private var devices: [MTDeviceRef] = []
    private var multitouchActive = false

    // Swipe tracking
    private var scrollDeltaX: CGFloat = 0
    private var scrollDeltaY: CGFloat = 0
    private var scrollFingerCount: Int = 0
    private let swipeThreshold: CGFloat = 50

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
    private var circleDrawingActive = false                 // true while circle gesture is being drawn
    private var mouseEventTap: CFMachPort?                  // CGEvent tap for suppressing mouse during circle
    private var mouseEventTapRunLoopSource: CFRunLoopSource?

    // Triangle gesture detection (1-finger pressing down and drawing)
    private var trianglePoints: [(x: Float, y: Float)] = []
    private var triangleFired = false

    // Edge slider detection (1-finger press + slide along edge, fires repeatedly)
    private var edgeSlideLastY: Float?
    private var edgeSlideEdge: EdgeSide?
    private let edgeSlideZoneWidth: Float = 0.15   // leftmost/rightmost 15%
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
            if case .trackpadGesture = $0.input { return $0.isEnabled }
            return false
        }

        for trigger in trackpadTriggers {
            if case .trackpadGesture(let gesture) = trigger.input {
                registeredTriggers.append((id: trigger.id, gesture: gesture, actions: trigger.actions, appBundleID: trigger.appBundleID))
            }
        }

        guard !registeredTriggers.isEmpty else { return }

        setupNSEventMonitors()
        setupMultitouchMonitoring()

        NSLog("[TrackpadMonitor] Registered %d gesture triggers", registeredTriggers.count)
    }

    // MARK: - Multitouch monitoring via private framework

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

        // Collect finger data from raw touch buffer using detected stride
        var fingerXPositions: [Float] = []
        var liveTouchPoints: [TouchPoint] = []
        if let raw = rawTouches, activeFingersCount > 0 {
            // Only detect stride when we have 2+ fingers (need two structs to measure)
            if touchStride == 0 && activeFingersCount >= 2 {
                touchStride = detectTouchStride(raw: raw, numTouches: activeFingersCount)
            }
            let stride = touchStride > 0 ? touchStride : MemoryLayout<MTTouch>.stride

            for i in 0..<activeFingersCount {
                let t = readTouch(from: raw, at: i * stride)
                fingerXPositions.append(t.x)
                // Only include in live view if position is valid (not a ghost at 0,0)
                if t.x > 0.001 || t.y > 0.001 {
                    liveTouchPoints.append(TouchPoint(
                        id: Int(t.fingerID),
                        x: t.x,
                        y: t.y,
                        size: t.majorAxis
                    ))
                }
            }


            // Track single finger position for zone click detection
            if activeFingersCount == 1 {
                let t0 = readTouch(from: raw, at: 0)
                lastSingleFingerPos = (x: t0.x, y: t0.y)
            } else {
                lastSingleFingerPos = nil
            }
        }
        // Update visual press state from real-time button query every frame
        // This is authoritative — avoids stale state from mismatched down/up events
        let anyButtonDown = NSEvent.pressedMouseButtons != 0
        LiveTouchState.shared.setPressed(anyButtonDown && !liveTouchPoints.isEmpty)
        LiveTouchState.shared.update(liveTouchPoints)

        let previousFingers = currentFingers


        // New touch session (all fingers were off)
        // BUT: if a TipTap is pending (2→0→1 sequence), don't reset!
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

        // --- TipTap detection ---
        // TipTap = one finger holds, another taps. Sequence: 1→2→1 (or 1→2→0→1)

        // Track 1-finger resting phase
        if activeFingersCount == 1 {
            if oneFingerStartTime == nil {
                oneFingerStartTime = Date()
            }
            // Continuously update rest X position while 1 finger is down
            if fingerXPositions.count == 1 && fingerXPositions[0] > 0.01 {
                oneFingerRestX = fingerXPositions[0]
            }
        }

        // 1→2 transition: second finger just landed
        if activeFingersCount == 2 && previousFingers == 1 {
            twoFingerStartTime = Date()
            // Was the single finger resting long enough?
            if let restStart = oneFingerStartTime {
                let restDuration = Date().timeIntervalSince(restStart)
                hadOneFingerRest = restDuration >= tipTapMinRestTime
                if hadOneFingerRest {
                    tipTapPending = true
                    tipTapPendingTime = Date()
                    // TipTap armed
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
        // Note: don't check gestureConsumed here — TipTap uses its own tipTapPending guard
        // gestureConsumed stays true from initial touch and never resets since finger stays down
        if activeFingersCount == 1 && previousFingers == 2 && tipTapPending {
            // Check if the remaining finger is the original rester (same side of trackpad).
            // If it switched sides, this was the user swapping resting fingers, not a tap.
            if let restX = oneFingerRestX, fingerXPositions.count == 1 {
                let remainingX = fingerXPositions[0]
                let sameSide = (restX < 0.50 && remainingX < 0.50) || (restX >= 0.50 && remainingX >= 0.50)
                if sameSide {
                    checkAndFireTipTap()
                } else {
                    // Resting finger switched sides — this is a direction change, not a tap
                    tipTapPending = false
                    oneFingerRestX = remainingX
                    oneFingerStartTime = Date()
                }
            } else {
                checkAndFireTipTap()
            }
        }

        // 2→0 transition: tapper might have lifted — keep tipTapPending alive briefly
        // (the rester might reappear as 0→1 on the next frame)

        // 0→1 after a pending TipTap (2→0→1 sequence): fire it!
        if activeFingersCount == 1 && previousFingers == 0 && tipTapPending {
            checkAndFireTipTap()
        }

        // Timeout: if tipTapPending has been waiting too long, clear it
        if tipTapPending, let pt = tipTapPendingTime, Date().timeIntervalSince(pt) > tipTapMaxTapDuration {
            // TipTap expired
            tipTapPending = false
        }

        // Reset TipTap Left/Right state if we go above 2 fingers
        if activeFingersCount > 2 {
            hadOneFingerRest = false
            tipTapPending = false
            oneFingerRestX = nil
            oneFingerStartTime = nil
        }

        // --- TipTap Middle detection (2→3→2) ---
        // Track 2-finger resting phase
        if activeFingersCount == 2 {
            if twoFingerRestTime == nil {
                twoFingerRestTime = Date()
            }
        }

        // 2→3 transition: third finger tapped
        if activeFingersCount == 3 && previousFingers == 2 {
            threeFingerStartTime = Date()
            if let restStart = twoFingerRestTime, Date().timeIntervalSince(restStart) >= tipTapMinRestTime {
                tipTapMiddlePending = true
            }
        }

        // 3→2 transition: tapper lifted — TipTap Middle!
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

        // Reset TipTap Middle state
        if activeFingersCount == 0 || activeFingersCount == 1 {
            twoFingerRestTime = nil
            tipTapMiddlePending = false
            threeFingerStartTime = nil
        }
        if activeFingersCount > 3 {
            tipTapMiddlePending = false
        }

        // --- Regular tap detection (all fingers lift together) ---
        if activeFingersCount == 0 && previousFingers > 0 && touchBegan != nil {
            let elapsed = Date().timeIntervalSince(touchBegan!)

            if elapsed < tapTimeout && !gestureConsumed {
                if peakFingers == 2 {
                    // Check for double-tap
                    let now = Date()
                    if let lastTap = lastTwoFingerTapTime, now.timeIntervalSince(lastTap) < doubleTapWindow {
                        // Double tap detected — cancel the pending single tap and fire double
                        doubleTapTimer?.cancel()
                        doubleTapTimer = nil
                        lastTwoFingerTapTime = nil
                        NSLog("[TrackpadMonitor] Detected 2-finger double tap")
                        DispatchQueue.main.async { [self] in
                            GestureLog.shared.logFromAnyThread("Detected 2-finger double tap", level: .detect)
                            fireGesture(.twoFingerDoubleTap)
                        }
                    } else {
                        // First tap — delay firing single tap to wait for possible second tap
                        lastTwoFingerTapTime = now
                        let timer = DispatchWorkItem { [weak self] in
                            guard let self else { return }
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
                } else {
                    let tapGesture: TrackpadGesture?
                    switch peakFingers {
                    case 3: tapGesture = .threeFingerTap
                    case 4: tapGesture = .fourFingerTap
                    case 5: tapGesture = .fiveFingerTap
                    default: tapGesture = nil
                    }
                    if let gesture = tapGesture {
                        NSLog("[TrackpadMonitor] Detected %d-finger tap (duration: %.2fs)", peakFingers, elapsed)
                        let fingers = peakFingers
                        let dur = elapsed
                        DispatchQueue.main.async { [self] in
                            GestureLog.shared.logFromAnyThread("Detected \(fingers)-finger tap (\(String(format: "%.2fs", dur)))", level: .detect)
                            fireGesture(gesture)
                        }
                    }
                }
            }

            touchBegan = nil
            peakFingers = 0
        }

        // --- Drawing gesture detection (1-finger pressing down and drawing) ---
        if activeFingersCount == 1, fingerXPositions.count == 1,
           let raw = rawTouches {
            let t0 = readTouch(from: raw, at: 0)
            let x = t0.x
            let y = t0.y
            // Only track when trackpad is clicked down and position is valid
            // Use NSEvent.pressedMouseButtons (real-time query) instead of stored
            // trackpadIsPressed to avoid race conditions between threads
            let isClickedNow = NSEvent.pressedMouseButtons & 0x1 != 0
            if x > 0.01 && y > 0.01 && isClickedNow {
                trackCirclePoint(x: x, y: y)
                trackTrianglePoint(x: x, y: y)
                trackEdgeDrag(x: x, y: y)
            } else {
                resetCircleState()
                resetTriangleState()
                resetEdgeDragState()
            }
        } else {
            resetCircleState()
            resetTriangleState()
            resetEdgeDragState()
        }
    }

    // MARK: - Circle gesture helpers

    private func trackCirclePoint(x: Float, y: Float) {
        circlePoints.append((x: x, y: y))

        // Update running centroid
        let n = Float(circlePoints.count)
        circleCenterX = circlePoints.reduce(0) { $0 + $1.x } / n
        circleCenterY = circlePoints.reduce(0) { $0 + $1.y } / n

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
                    circleCumulativeAngle = 0
                    circleLastFiredAngle = 0
                    circleFireCount = 0
                    circleStartTime = nil
                    circleLastAngle = angle
                }
                return
            }

            // Progressive firing: fire every N degrees of rotation, accelerating over time.
            if circleStartTime == nil {
                circleStartTime = Date()
                startSuppressingMouse()
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
                    DispatchQueue.main.async { [self] in
                        GestureLog.shared.logFromAnyThread("Circle: Counter-Clockwise (#\(circleFireCount))", level: .detect)
                        fireGesture(.circleCounterClockwise)
                    }
                } else {
                    DispatchQueue.main.async { [self] in
                        GestureLog.shared.logFromAnyThread("Circle: Clockwise (#\(circleFireCount))", level: .detect)
                        fireGesture(.circleClockwise)
                    }
                }
            }
        }
    }

    /// Check if the tracked path is roughly circular (not a line or zigzag)
    private func isPathCircular() -> Bool {
        guard circlePoints.count >= circleMinPoints else { return false }

        // Calculate distances from each point to the centroid
        let distances = circlePoints.map { p -> Float in
            let dx = p.x - circleCenterX
            let dy = p.y - circleCenterY
            return sqrt(dx * dx + dy * dy)
        }

        let meanDist = distances.reduce(0, +) / Float(distances.count)

        // Path must have a minimum radius (not just jitter in place)
        // but also a maximum — only small coin-sized circles should trigger
        guard meanDist > 0.02 && meanDist < 0.09 else { return false }

        // Check coefficient of variation (std dev / mean)
        // A circle has low variation, a line has high variation
        let variance = distances.map { ($0 - meanDist) * ($0 - meanDist) }.reduce(0, +) / Float(distances.count)
        let stdDev = sqrt(variance)
        let cv = stdDev / meanDist

        // A perfect circle has cv ≈ 0. Allow up to 0.45 for imperfect human circles.
        // Lines typically have cv > 0.5
        return cv < 0.45
    }

    private func resetCircleState() {
        circlePoints.removeAll()
        circleCumulativeAngle = 0
        circleLastAngle = nil
        circleCenterX = 0
        circleCenterY = 0
        circleLastFiredAngle = 0
        circleStartTime = nil
        circleFireCount = 0
        stopSuppressingMouse()
    }

    private func startSuppressingMouse() {
        let suppress = UserDefaults.standard.object(forKey: "GTTSuppressMouseDuringDrawing") as? Bool ?? true
        guard suppress, !circleDrawingActive else { return }
        circleDrawingActive = true

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

        mouseEventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        mouseEventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopSuppressingMouse() {
        guard circleDrawingActive else { return }
        circleDrawingActive = false
        if let tap = mouseEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = mouseEventTapRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            mouseEventTap = nil
            mouseEventTapRunLoopSource = nil
        }
    }

    // MARK: - Triangle gesture helpers

    private func trackTrianglePoint(x: Float, y: Float) {
        trianglePoints.append((x: x, y: y))
        // Don't check triangle if circle already fired this session, or triangle already fired
        guard !triangleFired, circleFireCount == 0, trianglePoints.count >= 20 else { return }
        // Start suppressing mouse once we have enough points for a potential drawing
        if trianglePoints.count == 20 { startSuppressingMouse() }
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
        stopSuppressingMouse()
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
            // Start tracking
            edgeSlideLastY = y
            edgeSlideEdge = side
            startSuppressingMouse()
            return
        }

        let deltaY = y - lastY
        if abs(deltaY) >= edgeSlideStep {
            // Fire once per step, then advance the anchor
            let gesture: TrackpadGesture
            switch (side, deltaY > 0) {
            case (.left, true):   gesture = .leftEdgeSlideUp
            case (.left, false):  gesture = .leftEdgeSlideDown
            case (.right, true):  gesture = .rightEdgeSlideUp
            case (.right, false): gesture = .rightEdgeSlideDown
            }
            edgeSlideLastY = y
            DispatchQueue.main.async { [self] in
                fireGesture(gesture)
            }
        }
    }

    private func resetEdgeDragState() {
        edgeSlideLastY = nil
        edgeSlideEdge = nil
        stopSuppressingMouse()
    }

    // MARK: - Position click detection

    private func handlePositionClick() {
        guard !positionClickFired, currentFingers == 1,
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

        if let gesture = gesture {
            positionClickFired = true
            DispatchQueue.main.async { [self] in
                GestureLog.shared.logFromAnyThread("Position Click: \(gesture.rawValue) (x=\(String(format: "%.2f", x)), y=\(String(format: "%.2f", y)))", level: .detect)
                fireGesture(gesture)
            }
        }
    }

    private func checkAndFireTipTap() {
        guard let twoStart = twoFingerStartTime,
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
            self?.trackpadIsPressed = true
            if (self?.currentFingers ?? 0) >= 2 {
                self?.pressDragDeltaX = 0
                self?.pressDragActive = true
            }
            self?.handlePositionClick()
        }
        let leftReleaseHandler: (NSEvent) -> Void = { [weak self] _ in
            self?.handlePressDragEnd()
            self?.trackpadIsPressed = false
            self?.positionClickFired = false
            self?.resetCircleState()
            self?.resetTriangleState()
            self?.resetEdgeDragState()
        }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: scrollHandler) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { e in scrollHandler(e); return e }) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .magnify, handler: magnifyHandler) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .magnify, handler: { e in magnifyHandler(e); return e }) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .rotate, handler: rotateHandler) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .rotate, handler: { e in rotateHandler(e); return e }) {
            monitors.append(m)
        }
        // Left mouse — gesture logic + visual
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
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: dragHandler) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged, handler: { e in dragHandler(e); return e }) {
            monitors.append(m)
        }
        // Right mouse — 2-finger click on trackpad is a right-click by default
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
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDragged, handler: dragHandler) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDragged, handler: { e in dragHandler(e); return e }) {
            monitors.append(m)
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
            fireGesture(gesture)
        }
        pressDragDeltaX = 0; pressDragActive = false
    }

    // MARK: - Scroll / Swipe handling

    private func handleScroll(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }

        if event.phase == .began {
            scrollDeltaX = 0; scrollDeltaY = 0
            let touches = event.touches(matching: .touching, in: nil)
            scrollFingerCount = max(touches.count, 2)
        }

        scrollDeltaX += event.scrollingDeltaX
        scrollDeltaY += event.scrollingDeltaY

        // Only consume gesture after meaningful scroll movement (preserves taps)
        if abs(scrollDeltaX) > 10 || abs(scrollDeltaY) > 10 {
            gestureConsumed = true
        }

        if event.phase == .ended || event.phase == .cancelled {
            let absX = abs(scrollDeltaX); let absY = abs(scrollDeltaY)
            guard absX > swipeThreshold || absY > swipeThreshold else {
                scrollDeltaX = 0; scrollDeltaY = 0; return
            }
            let gesture: TrackpadGesture?
            if absX > absY {
                gesture = swipeGesture(fingers: scrollFingerCount, direction: scrollDeltaX > 0 ? .left : .right)
            } else {
                gesture = swipeGesture(fingers: scrollFingerCount, direction: scrollDeltaY > 0 ? .up : .down)
            }
            if let gesture = gesture { fireGesture(gesture) }
            scrollDeltaX = 0; scrollDeltaY = 0
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
            if magnification > 0.1 { fireGesture(.twoFingerPinchOut) }
            else if magnification < -0.1 { fireGesture(.twoFingerPinchIn) }
            magnification = 0
        }
    }

    // MARK: - Rotate

    private func handleRotate(_ event: NSEvent) {
        if event.phase == .began { rotation = 0 }
        rotation += CGFloat(event.rotation)
        if abs(rotation) > 1 { gestureConsumed = true }
        if event.phase == .ended || event.phase == .cancelled {
            if rotation > 5 { fireGesture(.twoFingerRotateRight) }
            else if rotation < -5 { fireGesture(.twoFingerRotateLeft) }
            rotation = 0
        }
    }

    // MARK: - Fire

    private func fireGesture(_ gesture: TrackpadGesture) {
        NSLog("[TrackpadMonitor] Detected gesture: %@", gesture.rawValue)

        // Record every detected gesture for statistics (always, even when paused)
        GestureStatistics.shared.recordDetectionFromAnyThread(gesture.rawValue)

        // Check global toggle — detect but don't fire when disabled
        let globalEnabled = UserDefaults.standard.object(forKey: "GTTGlobalEnabled") as? Bool ?? true
        guard globalEnabled else {
            GestureLog.shared.logFromAnyThread("Gesture \(gesture.rawValue) — paused", level: .noMatch)
            return
        }

        // Get the frontmost app's bundle ID
        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Find matching triggers, split into app-specific and global
        let matching = registeredTriggers.filter { $0.gesture == gesture }
        let appSpecific = matching.filter { $0.appBundleID != nil && $0.appBundleID == frontBundleID }
        let global = matching.filter { $0.appBundleID == nil }

        // App-specific triggers take priority — if any exist for this app, skip globals
        let toFire = appSpecific.isEmpty ? global : appSpecific

        if toFire.isEmpty {
            GestureLog.shared.logFromAnyThread("Gesture \(gesture.rawValue) — no matching trigger", level: .noMatch)
        } else {
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
    }

    /// Test-only: directly fire a gesture through the normal pipeline
    func fireGestureForTest(_ gesture: TrackpadGesture) {
        fireGesture(gesture)
    }

    func unregisterAll() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        registeredTriggers.removeAll()
        trackpadIsPressed = false

        if multitouchActive {
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
        }
    }

    deinit {
        unregisterAll()
    }
}
