import AppKit
import SwiftUI

/// The menu bar panel: the package list, with details pushed on top.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .brewMissing:
                BrewMissingView()
            case .ready:
                ZStack {
                    if let ref = model.path.last {
                        PackageDetailView(ref: ref)
                            .id(ref)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        PackageListView()
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .clipped()
            }
        }
        .background(WindowKeyObserver(
            onOpen: { model.panelDidOpen() },
            onClose: { model.panelDidClose() }))
    }
}

/// Reports when the menu bar panel opens and closes (it becomes and resigns key window).
struct WindowKeyObserver: NSViewRepresentable {
    var onOpen: () -> Void
    var onClose: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onOpen = onOpen
        view.onClose = onClose
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onOpen = onOpen
        view.onClose = onClose
    }

    final class ObserverView: NSView {
        var onOpen: (() -> Void)?
        var onClose: (() -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.onOpen?() })
            observers.append(center.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.onClose?() })
            if window.isKeyWindow { onOpen?() }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

struct BrewMissingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Homebrew Not Found", systemImage: "mug")
            } description: {
                Text("Gingerbrew manages packages installed with Homebrew. Install Homebrew, then check again.")
            } actions: {
                Link("Get Homebrew", destination: URL(string: "https://brew.sh")!)
                    .buttonStyle(.borderedProminent)
                Button("Check Again") { model.retryLocatingBrew() }
            }
            Button("Quit Gingerbrew") { NSApp.terminate(nil) }
                .buttonStyle(.link)
                .padding(.bottom, 12)
        }
    }
}
