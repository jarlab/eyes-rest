/// Short suggestions shown on the break overlay.
public enum BreakTips {
    public static let all: [String] = [
        "Blink slowly a few times — we blink less when looking at screens.",
        "Let your eyes rest on the farthest thing you can see.",
        "If there's a window nearby, look outside.",
        "Close your eyes and take a slow, deep breath.",
        "Drop your shoulders and unclench your jaw.",
        "Roll your shoulders back a few times.",
        "Slowly look up, down, left and right.",
        "Sit back and let your gaze go soft.",
        "Take a sip of water.",
        "Check your posture: feet flat, back supported.",
    ]

    /// The tip at `index` modulo the number of tips; any integer, including negatives, is valid.
    public static func tip(for index: Int) -> String {
        let count = all.count
        return all[(index % count + count) % count]
    }
}
