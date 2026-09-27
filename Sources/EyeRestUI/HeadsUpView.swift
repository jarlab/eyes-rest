import EyeRestCore
import SwiftUI

/// The heads-up pill shown in the last seconds before a break.
struct HeadsUpView: View {
    static let height: CGFloat = 60

    let secondsLeft: Int
    let allowSnooze: Bool
    let snoozeMinutes: Int
    let actions: HeadsUpController.Actions

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                // Reserves the width of the longest message so the pill keeps its size while counting down.
                Text(StatusText.headsUpText(secondsLeft: 10))
                    .hidden()
                    .accessibilityHidden(true)
                Text(StatusText.headsUpText(secondsLeft: secondsLeft))
            }
            .font(.body.weight(.medium))
            .monospacedDigit()
            Spacer(minLength: 8)
            if allowSnooze {
                Button(StatusText.snoozeButtonTitle(minutes: snoozeMinutes), action: actions.snooze)
            }
            Button("Start Now", action: actions.startNow)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
    }
}
