import AppKit

/// The menu-bar icon, its optional countdown and its menu.
///
/// The menu's items are created once, in `menuNeedsUpdate(_:)`. After that only their title, visibility and enabled
/// state change, so the open menu can follow the 1 Hz tick without flicker or losing the highlighted item.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var remindNow: @MainActor () -> Void
        /// Pauses for the given number of seconds, or until resumed when nil.
        var pause: @MainActor (TimeInterval?) -> Void
        var resume: @MainActor () -> Void
        var resetTimer: @MainActor () -> Void
        var showSettings: @MainActor () -> Void
        var showAbout: @MainActor () -> Void
    }

    /// Everything the icon and menu show.
    struct Display: Equatable {
        enum Phase: Equatable {
            case counting, reminding, paused, suspended
        }

        var phase: Phase
        /// The countdown next to the icon, or nil for the icon alone.
        var countdown: String?
        var statusLine: String
    }

    /// References to the items that change while the menu exists.
    private struct MenuItems {
        let status: NSMenuItem
        let remindNow: NSMenuItem
        let pause: NSMenuItem
        let resume: NSMenuItem
        let resetTimer: NSMenuItem
    }

    /// The timed entries of the Pause submenu, in minutes.
    private static let pauseOptions: [(title: String, minutes: Int)] = [
        ("For 30 Minutes", 30),
        ("For 1 Hour", 60),
        ("For 2 Hours", 120),
    ]

    private static let countdownFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let actions: Actions
    private var display: Display
    private var menuItems: MenuItems?
    private var isMenuOpen = false
    /// What the button currently shows, so it is only touched when something changes.
    private var shownSymbol: String?
    private var shownCountdown: String?

    init(display: Display, actions: Actions) {
        self.display = display
        self.actions = actions
        super.init()
        statusItem.autosaveName = "EyeRestStatusItem"
        statusItem.button?.setAccessibilityLabel("EyeRest")
        statusItem.button?.imagePosition = .imageOnly
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        updateButton()
    }

    func update(_ display: Display) {
        guard display != self.display else { return }
        self.display = display
        updateButton()
        if isMenuOpen { updateMenuItems() }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menuItems == nil { menuItems = buildMenu() }
        updateMenuItems()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    // MARK: - Button

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let symbol = display.phase.symbolName
        if symbol != shownSymbol {
            shownSymbol = symbol
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
        }
        if display.countdown != shownCountdown {
            shownCountdown = display.countdown
            if let countdown = display.countdown {
                button.attributedTitle = NSAttributedString(string: countdown, attributes: [.font: Self.countdownFont])
                button.imagePosition = .imageLeading
            } else {
                button.title = ""
                button.imagePosition = .imageOnly
            }
        }
        if button.accessibilityValue() as? String != display.statusLine {
            button.setAccessibilityValue(display.statusLine)
        }
    }

    // MARK: - Menu

    private func buildMenu() -> MenuItems {
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let remindNow = actionItem("Remind Me Now", action: #selector(remindNow), key: "r")
        menu.addItem(remindNow)

        let pauseMenu = NSMenu()
        pauseMenu.autoenablesItems = false
        for option in Self.pauseOptions {
            let item = actionItem(option.title, action: #selector(pauseForMinutes(_:)))
            item.tag = option.minutes
            pauseMenu.addItem(item)
        }
        pauseMenu.addItem(.separator())
        pauseMenu.addItem(actionItem("Until I Resume", action: #selector(pauseUntilResumed)))
        let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
        pause.submenu = pauseMenu
        menu.addItem(pause)

        let resume = actionItem("Resume", action: #selector(resume))
        menu.addItem(resume)

        let resetTimer = actionItem("Reset Timer", action: #selector(resetTimer))
        menu.addItem(resetTimer)

        menu.addItem(.separator())
        menu.addItem(actionItem("Settings…", action: #selector(showSettings), key: ","))
        menu.addItem(actionItem("About EyeRest", action: #selector(showAbout)))
        let quit = NSMenuItem(title: "Quit EyeRest", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        return MenuItems(status: status, remindNow: remindNow, pause: pause, resume: resume, resetTimer: resetTimer)
    }

    /// Brings the existing items in line with `display`, touching only properties whose value changes.
    private func updateMenuItems() {
        guard let items = menuItems else { return }
        let phase = display.phase
        items.status.setTitle(display.statusLine)
        items.remindNow.setHidden(phase == .reminding)
        items.pause.setHidden(phase == .paused)
        items.resume.setHidden(phase != .paused)
        items.resetTimer.setEnabled(phase == .counting)
    }

    private func actionItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func remindNow() { actions.remindNow() }
    @objc private func pauseForMinutes(_ sender: NSMenuItem) { actions.pause(TimeInterval(sender.tag) * 60) }
    @objc private func pauseUntilResumed() { actions.pause(nil) }
    @objc private func resume() { actions.resume() }
    @objc private func resetTimer() { actions.resetTimer() }
    @objc private func showSettings() { actions.showSettings() }
    @objc private func showAbout() { actions.showAbout() }
}

private extension StatusItemController.Display.Phase {
    /// Template SF Symbols for the menu-bar icon.
    var symbolName: String {
        switch self {
        case .counting: "eye"
        case .reminding: "eye.fill"
        case .paused, .suspended: "pause.circle"
        }
    }
}

private extension NSMenuItem {
    func setTitle(_ newTitle: String) {
        if title != newTitle { title = newTitle }
    }

    func setHidden(_ hidden: Bool) {
        if isHidden != hidden { isHidden = hidden }
    }

    func setEnabled(_ enabled: Bool) {
        if isEnabled != enabled { isEnabled = enabled }
    }
}
