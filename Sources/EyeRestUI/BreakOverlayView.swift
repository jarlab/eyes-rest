import EyeRestCore
import SwiftUI

/// Live state of one break, shared by the overlay panels on every screen.
@MainActor
final class BreakOverlayModel: ObservableObject {
    /// How long Esc must be held to skip a break when skipping is turned off.
    static let emergencyHoldDuration: TimeInterval = 2

    let content: BreakOverlayContent
    let accessibility: AccessibilityOptions
    @Published var remaining: TimeInterval
    /// Fraction of the break elapsed, 0...1.
    @Published var progress: Double
    /// When the current Esc emergency hold began; nil while Esc is not being held.
    @Published var emergencyHoldStartedAt: Date?

    init(content: BreakOverlayContent, accessibility: AccessibilityOptions, remaining: TimeInterval, progress: Double) {
        self.content = content
        self.accessibility = accessibility
        self.remaining = remaining
        self.progress = progress
    }
}

/// The content of a break overlay panel: a dark, centred card of text, a countdown ring and the escape options.
struct BreakOverlayView: View {
    @ObservedObject var model: BreakOverlayModel
    let actions: BreakOverlayController.Actions

    private var content: BreakOverlayContent { model.content }
    private var options: AccessibilityOptions { model.accessibility }
    private var secondaryOpacity: Double { options.increaseContrast ? 1 : 0.8 }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "eye")
                .font(.system(size: 52, weight: .light))
                .accessibilityHidden(true)
                .padding(.bottom, 20)
            Text("Rest your eyes")
                .font(.system(size: 44, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 12)
            Text("Look at something at least 20 feet (6 m) away.")
                .font(.title2)
                .padding(.bottom, 10)
            Text(content.tip)
                .font(.title3)
                .foregroundStyle(.white.opacity(secondaryOpacity))
                .padding(.bottom, 36)
            CountdownRing(
                remaining: model.remaining,
                progress: model.progress,
                trackOpacity: options.increaseContrast ? 0.5 : 0.25,
                animatesProgress: !options.reduceMotion
            )
            .padding(.bottom, 36)
            buttons
            footer
                .frame(height: 64)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 620)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(options.reduceTransparency ? Color(white: 0.08).opacity(0.96) : Color.black.opacity(0.7))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var buttons: some View {
        if content.allowSnooze || content.allowSkip {
            HStack(spacing: 12) {
                if content.allowSnooze {
                    overlayButton(StatusText.snoozeButtonTitle(minutes: content.snoozeMinutes), action: actions.snooze)
                }
                if content.allowSkip {
                    overlayButton("Skip Break", action: actions.skip)
                }
            }
        }
    }

    /// A low-emphasis button with no keyboard shortcut, so Return and Space never end a break by accident.
    private func overlayButton(_ title: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .overlay {
                if options.increaseContrast {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white, lineWidth: 1)
                }
            }
    }

    @ViewBuilder
    private var footer: some View {
        if let startedAt = model.emergencyHoldStartedAt {
            EmergencyHoldCapsule(startedAt: startedAt, duration: BreakOverlayModel.emergencyHoldDuration)
        } else if content.allowSkip {
            Text("Press Esc to skip")
                .font(.callout)
                .foregroundStyle(.white.opacity(secondaryOpacity))
        }
    }
}

/// A ring that empties as the break runs down, with the remaining time inside. VoiceOver reads it as one element.
private struct CountdownRing: View {
    let remaining: TimeInterval
    let progress: Double
    let trackOpacity: Double
    /// When false (Reduce Motion) the ring steps once per update instead of sweeping smoothly.
    let animatesProgress: Bool

    private static let lineWidth: CGFloat = 6

    private var remainingFraction: Double { 1 - min(max(progress, 0), 1) }

    private var spokenRemaining: String {
        let seconds = remaining > 0 ? Int(remaining.rounded(.up)) : 0
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(trackOpacity), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: remainingFraction)
                .stroke(.white, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animatesProgress ? .linear(duration: 1) : nil, value: remainingFraction)
            Text(TimeFormatting.countdown(remaining))
                .font(.system(size: 40, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 168, height: 168)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue(spokenRemaining)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Shown while Esc is held to skip a break that cannot otherwise be skipped; the bar fills over the hold.
private struct EmergencyHoldCapsule: View {
    let startedAt: Date
    let duration: TimeInterval

    private static let barWidth: CGFloat = 220

    var body: some View {
        TimelineView(.animation) { timeline in
            let fraction = min(max(timeline.date.timeIntervalSince(startedAt) / duration, 0), 1)
            VStack(spacing: 8) {
                Text("Keep holding Esc to skip…")
                    .font(.callout.weight(.medium))
                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(width: Self.barWidth, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white)
                            .frame(width: Self.barWidth * fraction, height: 4)
                    }
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.white.opacity(0.14), in: Capsule())
        }
    }
}
