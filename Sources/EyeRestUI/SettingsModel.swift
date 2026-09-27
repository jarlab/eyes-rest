import EyeRestCore
import SwiftUI

/// Bridges `EyeRestSettings` to SwiftUI. Every change is clamped to the valid ranges, and `onChange` reports
/// only real changes.
@MainActor
public final class SettingsModel: ObservableObject {
    @Published private(set) var settings: EyeRestSettings

    /// Called after a user edit changes the settings.
    public var onChange: ((EyeRestSettings) -> Void)?

    public init(settings: EyeRestSettings) {
        self.settings = settings.clamped()
    }

    /// Applies `transform`, clamps the result and publishes it; calls `onChange` only if something changed.
    func update(_ transform: (inout EyeRestSettings) -> Void) {
        var updated = settings
        transform(&updated)
        updated = updated.clamped()
        guard updated != settings else { return }
        settings = updated
        onChange?(updated)
    }

    func restoreDefaults() {
        update { $0 = .default }
    }

    /// A binding to one setting that writes through `update(_:)`.
    func binding<T>(_ keyPath: WritableKeyPath<EyeRestSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
