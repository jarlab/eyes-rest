import AppKit

/// The application's main menu.
///
/// EyeRest is an accessory app, so this menu is never displayed. It exists so the Settings window gets the standard
/// key equivalents (⌘, ⌘Q ⌘W and the editing commands), which AppKit resolves through `NSApp.mainMenu`.
/// Items without a target travel the responder chain; the app-specific ones end at `AppDelegate`.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu("EyeRest", items: [
            NSMenuItem(title: "About EyeRest", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: ""),
            .separator(),
            NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ","),
            .separator(),
            NSMenuItem(title: "Quit EyeRest", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        menu.addItem(submenu("Edit", items: [
            // `undo:` and `redo:` are handled by NSWindow's undo manager but are not visible to Swift.
            // An uppercase key equivalent implies Shift, so Redo is ⇧⌘Z.
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"),
            .separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]))
        menu.addItem(submenu("Window", items: [
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ]))
        return menu
    }

    /// A top-level item whose submenu holds `items`.
    private static func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}

