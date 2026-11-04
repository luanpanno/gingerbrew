import AppKit
import SwiftUI

/// Adds a right-click (and Control-click) menu to the menu bar icon.
///
/// SwiftUI's `MenuBarExtra` only handles left clicks and doesn't expose its
/// `NSStatusItem`, so this watches for right clicks on the app's status bar
/// window and pops up a menu from the icon. Left clicks still open the panel.
@MainActor
final class StatusItemMenu: NSObject {
    static let shared = StatusItemMenu()

    private var monitor: Any?
    private var openSettingsAction: OpenSettingsAction?
    private weak var statusButton: NSButton?

    /// Called from the menu bar label, which can read SwiftUI's `openSettings`.
    func install(openSettings: OpenSettingsAction) {
        openSettingsAction = openSettings
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, let window = event.window, Self.isStatusBarWindow(window) else { return event }
            let isSecondary = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            // Other displays show a mirror of the icon without a real button; anchor
            // the menu to whichever copy was clicked so it opens on that display.
            guard isSecondary, let anchor = Self.button(in: window) ?? window.contentView else { return event }
            self.statusButton = Self.button(in: window) ?? Self.statusBarButton()
            self.showMenu(from: anchor)
            return nil
        }
    }

    private func showMenu(from anchor: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Open Gingerbrew", #selector(openPanelFromMenu)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("About Gingerbrew", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Gingerbrew", #selector(quit), key: "q"))

        let button = anchor as? NSButton
        button?.highlight(true)
        let origin = NSPoint(x: 0, y: anchor.isFlipped ? anchor.bounds.maxY + 5 : -5)
        menu.popUp(positioning: nil, at: origin, in: anchor)
        button?.highlight(false)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func openPanelFromMenu() {
        // Wait for the menu to finish closing, or the click lands in its tracking loop.
        DispatchQueue.main.async { self.openPanel() }
    }

    /// Opens the panel exactly as a left click on the icon does.
    func openPanel() {
        guard let button = statusButton ?? Self.statusBarButton() else { return }
        // The panel closes as soon as it loses focus, so the app has to be active first.
        NSApp.activate(ignoringOtherApps: true)

        // Since macOS 26 the system hosts status items and delivers clicks to the app
        // over a scene connection, so neither `performClick` nor synthetic mouse events
        // reach SwiftUI. Ask the status item to open its content the way a click does.
        let request = NSSelectorFromString("_requestExpandedInterfaceSession")
        if let item = Self.statusItem(of: button), item.responds(to: request) {
            _ = item.perform(request)
        } else {
            // Older systems: the button's action is what a click triggers.
            button.performClick(nil)
        }
    }

    private static func statusItem(of button: NSButton) -> NSObject? {
        let getter = NSSelectorFromString("_statusItem")
        guard button.responds(to: getter) else { return nil }
        return button.perform(getter)?.takeUnretainedValue() as? NSObject
    }

    /// The real status item button; the other status bar windows hold mirror copies for other displays.
    private static func statusBarButton() -> NSButton? {
        for window in NSApp.windows where isStatusBarWindow(window) {
            if let button = button(in: window) { return button }
        }
        return nil
    }

    @objc private func openSettings() {
        AppActions.openSettings(openSettingsAction)
    }

    @objc private func showAbout() {
        AppActions.showAbout()
    }

    @objc private func quit() {
        AppActions.quit()
    }

    // MARK: Finding the status item

    private static func isStatusBarWindow(_ window: NSWindow) -> Bool {
        NSStringFromClass(type(of: window)).contains("StatusBarWindow")
    }

    private static func button(in window: NSWindow) -> NSButton? {
        guard let content = window.contentView else { return nil }
        if let button = content as? NSButton { return button }
        var queue = content.subviews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let button = view as? NSButton { return button }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }
}

/// App-level commands shared by the gear menu and the right-click menu.
@MainActor
enum AppActions {
    static func openSettings(_ action: OpenSettingsAction?) {
        NSApp.activate(ignoringOtherApps: true)
        action?()
    }

    static func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    static func quit() {
        NSApp.terminate(nil)
    }
}
