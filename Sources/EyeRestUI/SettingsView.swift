import EyeRestCore
import SwiftUI

/// The settings form under the Aero header strip. Every change applies immediately; there is no Save button.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var launchAtLogin: LaunchAtLoginModel

    /// The interval as typed, committed on Return, on focus loss or by the stepper.
    @State private var intervalDraft: Int
    @FocusState private var isIntervalFocused: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(model: SettingsModel, launchAtLogin: LaunchAtLoginModel) {
        self.model = model
        self.launchAtLogin = launchAtLogin
        _intervalDraft = State(initialValue: model.settings.intervalMinutes)
    }

    private var settings: EyeRestSettings { model.settings }

    var body: some View {
        Form {
            Section {
                intervalRow
                Picker("Look away for", selection: model.binding(\.reminderSeconds)) {
                    ForEach(Self.choices(EyeRestSettings.reminderPresets, including: settings.reminderSeconds),
                            id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Play a sound", isOn: model.binding(\.playSound))
                Toggle("Show time remaining in menu bar", isOn: model.binding(\.showCountdownInMenuBar))
            } header: {
                header
            }

            Section {
                openAtLoginRows
            } footer: {
                HStack {
                    Spacer()
                    // Leaves the login item alone: that is a system setting, not one of EyeRest's.
                    Button("Restore Defaults", action: model.restoreDefaults)
                }
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }

    // MARK: - Rows

    private var header: some View {
        let minutes = settings.intervalMinutes
        return AeroHeaderStrip(
            icon: Image(nsImage: NSApp.applicationIconImage),
            subtitle: "A gentle reminder to look away every \(minutes == 1 ? "minute" : "\(minutes) minutes").",
            dark: colorScheme == .dark,
            reduceTransparency: reduceTransparency,
            increaseContrast: colorSchemeContrast == .increased
        )
        // A grouped form insets section headers 10 pt from the sections; the strip spans their full width.
        .padding(.horizontal, -10)
        .padding(.bottom, 8)
    }

    private var intervalRow: some View {
        LabeledContent("Remind me every") {
            HStack(spacing: 6) {
                TextField("Minutes", value: $intervalDraft, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .focused($isIntervalFocused)
                    .onSubmit(commitInterval)
                // Steps from the typed value, so a draft isn't lost by clicking the stepper.
                Stepper("Minutes", value: steppedInterval, in: EyeRestSettings.intervalRange)
                    .labelsHidden()
                Text("minutes")
            }
        }
        .onChange(of: isIntervalFocused) { _, focused in
            if !focused { commitInterval() }
        }
        .onChange(of: settings.intervalMinutes) { _, minutes in
            intervalDraft = minutes
        }
    }

    @ViewBuilder private var openAtLoginRows: some View {
        Toggle(isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) })) {
            Text("Open at login")
            if !launchAtLogin.isAvailable {
                Text("Install EyeRest in your Applications folder to enable this.")
            }
            if let error = launchAtLogin.lastError {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .disabled(!launchAtLogin.isAvailable)

        if launchAtLogin.requiresApproval {
            LabeledContent {
                Button("Open Login Items…", action: launchAtLogin.openLoginItemsSettings)
            } label: {
                Text("Approve EyeRest in System Settings to open it at login.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var steppedInterval: Binding<Int> {
        Binding(
            get: { intervalDraft },
            set: { minutes in
                intervalDraft = minutes
                commitInterval()
            }
        )
    }

    /// Applies the typed interval (clamped), then shows the value in effect. This also reverts text that
    /// could not be parsed as a number.
    private func commitInterval() {
        model.update { $0.intervalMinutes = intervalDraft }
        intervalDraft = model.settings.intervalMinutes
    }

    /// The presets plus `current` when it is not one of them, so the picker never shows a blank selection.
    private static func choices(_ presets: [Int], including current: Int) -> [Int] {
        presets.contains(current) ? presets : (presets + [current]).sorted()
    }
}
