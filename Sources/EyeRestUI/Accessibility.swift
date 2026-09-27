import AppKit

/// The display accessibility preferences (System Settings › Accessibility › Display) that change how
/// EyeRest's panels look and move.
struct AccessibilityOptions: Equatable {
    var reduceMotion = false
    var reduceTransparency = false
    var increaseContrast = false

    /// The preferences as currently set by the user.
    static var current: AccessibilityOptions {
        let workspace = NSWorkspace.shared
        return AccessibilityOptions(
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast
        )
    }
}

enum VoiceOver {
    /// Asks VoiceOver to speak `message` at high priority. Does nothing when VoiceOver is off.
    @MainActor
    static func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}
