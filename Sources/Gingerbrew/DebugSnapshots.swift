#if DEBUG
import AppKit
import GingerbrewCore
import SwiftUI

/// Development aid: renders the panel in several states to PNG files and quits.
///
///     GINGERBREW_SNAPSHOT_DIR=/tmp/shots swift run Gingerbrew
@MainActor
enum DebugSnapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["GINGERBREW_SNAPSHOT_DIR"].map(URL.init(fileURLWithPath:))
    }

    static func run(into directory: URL) {
        Task {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let model = AppModel()
            while !model.hasLoadedInstalled || model.isIndexLoading || model.indexUpdatedAt == nil {
                try? await Task.sleep(for: .milliseconds(200))
            }

            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                let (window, host) = makeWindow(RootView().environment(model), appearance: appearance)
                await settle()
                save(host, directory.appendingPathComponent("1-list-\(suffix).png"))

                model.query = "fire"
                try? await Task.sleep(for: .milliseconds(600))
                await settle()
                save(host, directory.appendingPathComponent("2-search-\(suffix).png"))

                if let entry = model.recommendations.first {
                    model.open(entry.ref)
                    await settle(seconds: 3)
                    save(host, directory.appendingPathComponent("4-detail-available-\(suffix).png"))
                    model.goBack()
                }
                model.query = ""
                if let target = model.outdated.first {
                    model.open(target.ref)
                    await settle(seconds: 1.5)
                    save(host, directory.appendingPathComponent("3-detail-installed-\(suffix).png"))
                    model.goBack()
                }
                let cask = model.installed.first { $0.kind == .cask && PackageMetadata.appURL(for: $0) != nil }
                if let cask {
                    model.open(cask.ref)
                    await settle(seconds: 1.5)
                    save(host, directory.appendingPathComponent("5-detail-cask-\(suffix).png"))
                    model.goBack()
                }
                window.close()

                let (settingsWindow, settingsHost) = makeWindow(
                    SettingsView().environment(model), appearance: appearance, size: nil)
                await settle()
                save(settingsHost, directory.appendingPathComponent("6-settings-\(suffix).png"))
                settingsWindow.close()
            }
            print("Snapshots written to \(directory.path)")
            NSApp.terminate(nil)
        }
    }

    private static func makeWindow<V: View>(
        _ view: V, appearance: NSAppearance.Name, size: NSSize? = NSSize(width: 360, height: 540)
    ) -> (NSWindow, NSView) {
        let host = NSHostingView(rootView: view.frame(
            width: size?.width, height: size?.height).background(Color(nsColor: .windowBackgroundColor)))
        let fitting = size ?? host.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -5000, y: -5000), size: fitting),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        window.orderFrontRegardless()
        return (window, host)
    }

    private static func settle(seconds: Double = 0.8) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func save(_ view: NSView, _ url: URL) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
