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
        #endif
    }
}

/// The menu bar icon, with the number of available updates next to it.
struct MenuBarLabel: View {
    let updateCount: Int

    var body: some View {
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
