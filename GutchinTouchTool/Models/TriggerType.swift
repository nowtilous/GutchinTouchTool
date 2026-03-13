import Foundation

enum TriggerCategory: String, CaseIterable, Identifiable, Codable {
    case trackpad = "Trackpad"
    case keyboard = "Keyboard"
    case normalMouse = "Normal Mouse"
    case drawings = "Drawings"
    case otherTriggers = "Other Triggers"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .trackpad: return "hand.point.up"
        case .keyboard: return "keyboard"
        case .normalMouse: return "computermouse.fill"
        case .drawings: return "hand.draw"
        case .otherTriggers: return "ellipsis.circle"
        }
    }
}

enum TrackpadGesture: String, CaseIterable, Identifiable, Codable {
    // 2-finger gestures
    case twoFingerSwipeUp = "2 Finger Swipe Up"
    case twoFingerSwipeDown = "2 Finger Swipe Down"
    case twoFingerSwipeLeft = "2 Finger Swipe Left"
    case twoFingerSwipeRight = "2 Finger Swipe Right"
    case twoFingerPinchIn = "2 Finger Pinch In"
    case twoFingerPinchOut = "2 Finger Pinch Out"
    case twoFingerRotateLeft = "Rotate Left"
    case twoFingerRotateRight = "Rotate Right"
    case twoFingerTap = "2 Finger Tap"
    case twoFingerDoubleTap = "2 Finger Double Tap"
    case twoFingerClick = "2 Finger Click"

    // 3-finger gestures
    case threeFingerSwipeUp = "3 Finger Swipe Up"
    case threeFingerSwipeDown = "3 Finger Swipe Down"
    case threeFingerSwipeLeft = "3 Finger Swipe Left"
    case threeFingerSwipeRight = "3 Finger Swipe Right"
    case threeFingerTap = "3 Finger Tap"
    case threeFingerClick = "3 Finger Click"

    // 4-finger gestures
    case fourFingerSwipeUp = "4 Finger Swipe Up"
    case fourFingerSwipeDown = "4 Finger Swipe Down"
    case fourFingerSwipeLeft = "4 Finger Swipe Left"
    case fourFingerSwipeRight = "4 Finger Swipe Right"
    case fourFingerTap = "4 Finger Tap"
    case fiveFingerTap = "5 Finger Tap"

    // TipTap gestures (one finger rests, another taps)
    case tipTapLeft = "TipTap Left"
    case tipTapRight = "TipTap Right"
    case tipTapMiddle = "TipTap Middle"

    // Circular gestures
    case circleClockwise = "Circle Clockwise"
    case circleCounterClockwise = "Circle Counter-Clockwise"

    // Position clicks (click at specific trackpad zones)
    case cornerClickTopLeft = "Corner Click Top Left"
    case cornerClickTopRight = "Corner Click Top Right"
    case cornerClickBottomLeft = "Corner Click Bottom Left"
    case cornerClickBottomRight = "Corner Click Bottom Right"
    case middleClickTop = "Middle Click Top"
    case middleClickBottom = "Middle Click Bottom"

    var id: String { rawValue }
}

enum MouseButton: String, CaseIterable, Identifiable, Codable {
    case button3 = "Middle Click (Button 3)"
    case button4 = "Button 4"
    case button5 = "Button 5"
    case button6 = "Button 6"
    case button7 = "Button 7"

    var id: String { rawValue }
}

struct KeyboardShortcut: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    enum CodingKeys: String, CodingKey {
        case keyCode, modifierRawValue
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let raw = try container.decode(UInt.self, forKey: .modifierRawValue)
        modifiers = NSEvent.ModifierFlags(rawValue: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifierRawValue)
    }
}

import AppKit

func keyCodeToString(_ keyCode: UInt16) -> String {
    let mapping: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
        51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
        109: "F10", 111: "F12", 113: "F15", 115: "Home", 116: "⇞",
        117: "⌦", 118: "F4", 119: "End", 120: "F2", 121: "⇟",
        122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
    return mapping[keyCode] ?? "Key\(keyCode)"
}

extension NSEvent.ModifierFlags: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}
