import AppKit
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate                 // weak property
    app.setActivationPolicy(.accessory)     // needed for swift run; LSUIElement covers the bundle
    withExtendedLifetime(delegate) { app.run() }
}
