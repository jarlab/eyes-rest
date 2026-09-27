import EyeRestCore
import SwiftUI

/// Bridges `EyeRestSettings` to SwiftUI. Every change is clamped to the valid ranges, and `onChange` reports
/// only real changes made through the UI.
@MainActor
public final class SettingsModel: ObservableObject {
    @Published public private(set) var settings: EyeRestSettings

    /// Called after a user edit changes the settings (not after `replace(with:)`).
    public var onChange: ((EyeRestSettings) -> Void)?

    public init(settings: EyeRestSettings) {
        self.settings = settings.clamped()
    }

    /// Applies `transform`, clamps the result and publishes it; calls `onChange` only if something changed.
    public func update(_ transform: (inout EyeRestSettings) -> Void) {
        var updated = settings
        transform(&updated)
        updated = updated.clamped()
        guard updated != settings else { return }
        settings = updated
        onChange?(updated)
    }

    /// Adopts settings changed elsewhere, without calling `onChange`.
    public func replace(with settings: EyeRestSettings) {
        let clamped = settings.clamped()
        guard clamped != self.settings else { return }
        self.settings = clamped
    }

    public func restoreDefaults() {
        update { $0 = .default }
    }

    /// A binding to one setting that writes through `update(_:)`.
    public func binding<T>(_ keyPath: WritableKeyPath<EyeRestSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
