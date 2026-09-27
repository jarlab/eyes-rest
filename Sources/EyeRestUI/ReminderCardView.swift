import EyeRestCore
import SwiftUI

/// The non-blocking reminder card: a frosted Aero glass pane with the countdown in a glossy glass ring (a few bubbles
/// rising from it), the message, and an aqua gel Done button. The view includes its own transparent shadow margin
/// (`Aero.shadowMargin`) and follows the environment's `colorScheme` (Dark Mode tints the glass down a step).
struct ReminderCardView: View {
    let remaining: TimeInterval
    /// Elapsed fraction of the reminder, 0...1.
    let progress: Double
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        HStack(spacing: 14) {
            AeroCountdownRing(progress: progress, label: TimeFormatting.countdown(remaining), dark: dark,
                              reduceTransparency: reduceTransparency, increaseContrast: increaseContrast)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time remaining")
                .accessibilityValue(Self.spokenSeconds(remaining))
                .accessibilityAddTraits(.updatesFrequently)

            VStack(alignment: .leading, spacing: 1) {
                Text("Time to rest your eyes")
                    .font(Aero.font(16, .semibold))
                    .foregroundStyle(Aero.ink(increaseContrast))
                    .etched(!increaseContrast)
                    .accessibilityAddTraits(.isHeader)
                Text("Look at something 20 feet (6 m) away.")
                    .font(Aero.font(13, .medium))
                    .foregroundStyle(Aero.inkSoft(increaseContrast))
                    .etched(!increaseContrast)
                Button("Done", action: onDone)
                    .buttonStyle(AeroGelButtonStyle(increaseContrast: increaseContrast))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 9)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .frame(width: Aero.cardWidth)
        .background(AeroGlassPanel(dark: dark, reduceTransparency: reduceTransparency,
                                   increaseContrast: increaseContrast))
        .padding(Aero.shadowMargin)
        .accessibilityElement(children: .contain)
    }

    /// "20 seconds", "1 second": whole seconds rounded up like the countdown, so it never says 0 while time remains.
    static func spokenSeconds(_ seconds: TimeInterval) -> String {
        let total = seconds > 0 ? Int(min(seconds.rounded(.up), 359_999)) : 0
        return total == 1 ? "1 second" : "\(total) seconds"
    }
}

/// The countdown: a glass disc with a recessed groove, the remaining time as a glossy aqua-to-lime tube that shrinks
/// counter-clockwise back to twelve o'clock, the time in the middle, and three bubbles rising off its upper right.
private struct AeroCountdownRing: View {
    var progress: Double
    var label: String
    var dark: Bool
    var reduceTransparency: Bool
    var increaseContrast: Bool

    private let size: CGFloat = 76
    private let tube: CGFloat = 7
    private let inset: CGFloat = 8

    var body: some View {
        let remainingFraction = 1 - (progress.isFinite ? min(max(progress, 0), 1) : 1)
        let groove = Circle().inset(by: inset)
        ZStack {
            AeroGlassDisc(dark: dark, increaseContrast: increaseContrast)
            groove.stroke(LinearGradient(colors: [Aero.rgb(0x1F5F99, increaseContrast ? 0.45 : 0.24),
                                                  Aero.rgb(0x1F5F99, increaseContrast ? 0.3 : 0.1)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: tube)
            if remainingFraction > 0.001 {
                Group {
                    groove.trim(from: 0, to: remainingFraction)
                        .stroke(AngularGradient(colors: increaseContrast
                                                    ? [Aero.rgb(0x0A6CC4), Aero.rgb(0x0F7A55)]
                                                    : [Aero.rgb(0x19B5EC), Aero.rgb(0x43C66E)],
                                                center: .center, startAngle: .zero,
                                                endAngle: .degrees(360 * remainingFraction)),
                                style: StrokeStyle(lineWidth: tube, lineCap: .round))
                        .shadow(color: Aero.rgb(0x2FC3F0, increaseContrast || reduceTransparency ? 0 : 0.45),
                                radius: 2.5)
                    // The tube's specular line, riding along its outer half.
                    Circle().inset(by: inset - tube * 0.22).trim(from: 0, to: remainingFraction)
                        .stroke(.white.opacity(0.65), style: StrokeStyle(lineWidth: tube * 0.3, lineCap: .round))
                        .blur(radius: 0.3)
                }
                .rotationEffect(.degrees(-90))
            }
            Text(label)
                .font(Aero.font(20, .semibold))
                .monospacedDigit()
                .foregroundStyle(Aero.ink(increaseContrast))
                .etched(!increaseContrast)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topLeading) {
            // Bubbles leaving the ring at about one o'clock and rising, clear of the title.
            if !reduceTransparency {
                ZStack(alignment: .topLeading) {
                    AeroBubble(diameter: 6.5).offset(x: 0, y: 17)
                    AeroBubble(diameter: 4.5).offset(x: 6, y: 7.5)
                    AeroBubble(diameter: 3).offset(x: 9.5, y: 0)
                }
                .frame(width: 13, height: 24, alignment: .topLeading)
                .offset(x: 66, y: -9)
            }
        }
    }
}
