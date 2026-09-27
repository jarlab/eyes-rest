import AppKit

/// Plays the chime at the end of a completed break.
@MainActor
public final class SoundPlayer {
    /// Loaded on first use and reused, so repeated chimes do not reload the file.
    private lazy var breakEndedSound: NSSound? = {
        let sound = NSSound(named: "Glass")
        sound?.volume = 0.6
        return sound
    }()

    public init() {}

    /// Plays "Glass" at 60% volume, restarting it if it is still playing.
    public func playBreakEnded() {
        guard let sound = breakEndedSound else { return }
        sound.stop()
        sound.play()
    }
}
