import EyeRestCore
import SwiftUI

/// Window state that is not a setting.
@MainActor
final class SettingsPresentation: ObservableObject {
    /// Shows the first-launch welcome header above the form.
    @Published var showsWelcome = false
    /// The tallest the form may grow before it scrolls, so the window always fits on its screen.
    @Published var maxHeight: CGFloat = .infinity
}

/// The settings form. Every change applies immediately; there is no Save button.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var launchAtLogin: LaunchAtLoginModel
    @ObservedObject var presentation: SettingsPresentation

    /// The work interval as typed, committed on Return or when the field loses focus.
    @State private var workIntervalDraft: Int
    @FocusState private var isWorkIntervalFocused: Bool

    init(model: SettingsModel, launchAtLogin: LaunchAtLoginModel, presentation: SettingsPresentation) {
        self.model = model
        self.launchAtLogin = launchAtLogin
        self.presentation = presentation
        _workIntervalDraft = State(initialValue: model.settings.workIntervalMinutes)
    }

    private var settings: EyeRestSettings { model.settings }

    var body: some View {
        Form {
            if presentation.showsWelcome {
                welcomeSection
            }
            breaksSection
            skippingAndPausingSection
            generalSection
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(maxHeight: presentation.maxHeight)
        .onAppear(perform: launchAtLogin.refresh)
    }

    // MARK: - Sections

    private var welcomeSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "eye")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("EyeRest is running")
                        .font(.title3.weight(.semibold))
                    Text(
                        "Every \(TimeFormatting.duration(settings.workInterval)), EyeRest dims your screen for "
                            + "\(TimeFormatting.duration(settings.breakDuration)) so you can look at something "
                            + "about 20 feet (6 m) away. Use the eye icon in the menu bar to take a break early "
                            + "or pause."
                    )
                    Text(welcomeCaption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }
    }

    /// The Open at login tip that fits how EyeRest was installed, then the way back when the menu-bar icon is hidden.
    private var welcomeCaption: String {
        let hiddenIcon = "Can't see the icon? Open EyeRest again to come back here."
        switch launchAtLogin.availability {
        case .available where !launchAtLogin.isEnabled:
            return "Turn on Open at login below so breaks start automatically. " + hiddenIcon
        case .notInApplications:
            return "Move EyeRest to your Applications folder to have it open at login. " + hiddenIcon
        case .available, .notBundled:
            return hiddenIcon
        }
    }

    private var breaksSection: some View {
        Section {
            LabeledContent("Remind me every") {
                HStack(spacing: 6) {
                    TextField("Minutes", value: $workIntervalDraft, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 44)
                        .focused($isWorkIntervalFocused)
                        .onSubmit(commitWorkInterval)
                    Stepper(
                        "Minutes",
                        value: model.binding(\.workIntervalMinutes),
                        in: EyeRestSettings.workIntervalRange,
                        step: 1
                    )
                    .labelsHidden()
                    Text("minutes")
                }
            }
            .onChange(of: isWorkIntervalFocused) { _, focused in
                if !focused { commitWorkInterval() }
            }
            .onChange(of: settings.workIntervalMinutes) { _, minutes in
                workIntervalDraft = minutes
            }

            Picker("Break length", selection: model.binding(\.breakDurationSeconds)) {
                ForEach(
                    Self.choices(EyeRestSettings.breakDurationPresets, including: settings.breakDurationSeconds),
                    id: \.self
                ) { seconds in
                    Text(TimeFormatting.duration(TimeInterval(seconds))).tag(seconds)
                }
            }
            .pickerStyle(.menu)

            Toggle("Warn me 10 seconds before a break", isOn: model.binding(\.showHeadsUp))
            Toggle("Play a sound when a break ends", isOn: model.binding(\.playSounds))
        } header: {
            Text("Breaks")
        } footer: {
            // The welcome already explains the rule.
            if !presentation.showsWelcome {
                footnote("Based on the 20-20-20 rule: every 20 minutes, look 20 feet away for 20 seconds.")
            }
        }
    }

    private var skippingAndPausingSection: some View {
        Section {
            Toggle(isOn: model.binding(\.allowSkip)) {
                Text("Allow skipping breaks")
                if !settings.allowSkip {
                    Text("You can still skip in an emergency by holding Esc for 2 seconds.")
                }
            }
            // "Off" turns snoozing off and keeps the length for when it is turned back on.
            optionalMinutesPicker(
                selection: snoozeMinutes,
                presets: EyeRestSettings.postponePresets,
                current: settings.postponeMinutes,
                offTitle: "Off",
                itemTitle: { TimeFormatting.duration($0) }
            ) {
                Text("Snooze")
            }
            Toggle(isOn: model.binding(\.holdDuringCalls)) {
                Text("Hold breaks during calls")
                Text("While your camera or microphone is in use.")
            }
            // "Never" turns idle pausing off and keeps the threshold for when it is turned back on.
            optionalMinutesPicker(
                selection: awayMinutes,
                presets: EyeRestSettings.idleThresholdPresets,
                current: settings.idleThresholdMinutes,
                offTitle: "Never",
                itemTitle: { "After " + TimeFormatting.duration($0) }
            ) {
                Text("Pause when I'm away")
                Text("Time away from your Mac counts as a break.")
            }
        } header: {
            Text("Skipping & Pausing")
        }
    }

    private var generalSection: some View {
        Section {
            Toggle(isOn: launchAtLoginBinding) {
                Text("Open at login")
                if launchAtLogin.availability != .available {
                    Text("Install EyeRest in your Applications folder to enable this.")
                }
                if let error = launchAtLogin.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .disabled(launchAtLogin.availability != .available)

            if launchAtLogin.requiresApproval {
                LabeledContent {
                    Button("Open Login Items…", action: launchAtLogin.openLoginItemsSettings)
                } label: {
                    Text("Approve EyeRest in System Settings to open it at login.")
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Show time remaining in menu bar", isOn: model.binding(\.showCountdownInMenuBar))
        } header: {
            Text("General")
        } footer: {
            HStack {
                Spacer()
                // Leaves the login item alone: that is a system setting, not one of EyeRest's.
                Button("Restore Defaults", action: model.restoreDefaults)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    /// The snooze length in minutes, or nil while snoozing is off.
    private var snoozeMinutes: Binding<Int?> {
        Binding(
            get: { settings.allowPostpone ? settings.postponeMinutes : nil },
            set: { minutes in
                model.update {
                    $0.allowPostpone = minutes != nil
                    if let minutes { $0.postponeMinutes = minutes }
                }
            }
        )
    }

    /// The idle time before EyeRest pauses, in minutes, or nil while pausing when away is off.
    private var awayMinutes: Binding<Int?> {
        Binding(
            get: { settings.pauseWhenIdle ? settings.idleThresholdMinutes : nil },
            set: { minutes in
                model.update {
                    $0.pauseWhenIdle = minutes != nil
                    if let minutes { $0.idleThresholdMinutes = minutes }
                }
            }
        )
    }

    /// A menu of minute presets (plus `current` when it is not one of them), each titled by `itemTitle` from its
    /// duration in seconds, below an item titled `offTitle` that selects nil.
    private func optionalMinutesPicker<Label: View>(
        selection: Binding<Int?>,
        presets: [Int],
        current: Int,
        offTitle: String,
        itemTitle: @escaping (TimeInterval) -> String,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Picker(selection: selection) {
            Text(offTitle).tag(Int?.none)
            Divider()
            ForEach(Self.choices(presets, including: current), id: \.self) { minutes in
                Text(itemTitle(TimeInterval(minutes) * 60)).tag(Int?.some(minutes))
            }
        } label: {
            label()
        }
        .pickerStyle(.menu)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10) // aligns with the section header text
    }

    /// Applies the typed interval (clamped), then shows the value in effect. This also reverts text that
    /// could not be parsed as a number.
    private func commitWorkInterval() {
        model.update { $0.workIntervalMinutes = workIntervalDraft }
        workIntervalDraft = model.settings.workIntervalMinutes
    }

    /// The presets plus `current` when it is not one of them, so a picker never shows a blank selection.
    private static func choices(_ presets: [Int], including current: Int) -> [Int] {
        presets.contains(current) ? presets : (presets + [current]).sorted()
    }
}
