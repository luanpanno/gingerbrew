import AppKit
import SwiftUI

@main
struct GingerbrewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ViewState private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(model)
                .frame(width: 360, height: 540)
        } label: {
            MenuBarLabel(updateCount: model.outdated.count)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist sets LSUIElement; this also covers `swift run` during development.
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if let directory = DebugSnapshots.directory { DebugSnapshots.run(into: directory) }
        // GINGERBREW_TEST_OPEN=1 opens the panel the way the right-click menu's
        // "Open Gingerbrew" does, reports whether it appeared, and quits.
        if ProcessInfo.processInfo.environment["GINGERBREW_TEST_OPEN"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                StatusItemMenu.shared.openPanel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    let panel = NSApp.windows.first { "\(type(of: $0))".hasPrefix("MenuBarExtraWindow") }
                    print("panel open: \(panel?.isVisible == true)")
                    fflush(stdout)
                    NSApp.terminate(nil)
                }
            }
        }
        #endif
    }
}

/// The menu bar icon, with the number of available updates next to it.
struct MenuBarLabel: View {
    let updateCount: Int
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        icon
            .onAppear { StatusItemMenu.shared.install(openSettings: openSettings) }
    }

    @ViewBuilder
    private var icon: some View {
        if updateCount > 0 {
            HStack(spacing: 2) {
                Image(systemName: "mug.fill")
                Text("\(updateCount)")
            }
            .accessibilityLabel("Gingerbrew, \(updateCount) updates available")
        } else {
            Image(systemName: "mug")
                .accessibilityLabel("Gingerbrew")
        }
    }
}
