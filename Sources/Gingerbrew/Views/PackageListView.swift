import AppKit
import GingerbrewCore
import SwiftUI

struct PackageListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            SearchField(
                text: $model.query,
                placeholder: "Search packages",
                focusTrigger: model.isPanelVisible)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)

            Divider()

            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
                Divider()
            }

            content
                .frame(maxHeight: .infinity)

            if let operation = model.operation {
                Divider()
                OperationStatusView(operation: operation)
                    .padding(10)
            }

            Divider()
            footer
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.isSearchActive {
            searchResults
        } else if !model.hasLoadedInstalled {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.installed.isEmpty {
            ContentUnavailableView {
                Label("No Packages Installed", systemImage: "shippingbox")
            } description: {
                Text("Search above to find formulae and apps to install with Homebrew.")
            }
        } else {
            installedList
        }
    }

    private var installedList: some View {
        let outdated = model.outdated
        let upToDate = model.installed.filter { !$0.isOutdated }
        return List {
            if !outdated.isEmpty {
                Section("Updates Available") {
                    ForEach(outdated) { row(for: $0) }
                }
            }
            Section(outdated.isEmpty ? "Installed" : "Up to Date") {
                ForEach(upToDate) { row(for: $0) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var searchResults: some View {
        let installed = model.filteredInstalled
        let recommended = model.recommendations.map(Package.init(entry:))
        let indexUnavailable = model.indexUpdatedAt == nil
        if installed.isEmpty, recommended.isEmpty, !model.isSearching,
           !(indexUnavailable && model.isIndexLoading) {
            ContentUnavailableView.search(text: model.query)
        } else {
            List {
                if !installed.isEmpty {
                    Section("Installed") {
                        ForEach(installed) { row(for: $0) }
                    }
                }
                Section {
                    if indexUnavailable && model.isIndexLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Downloading the Homebrew catalogue…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let error = model.indexError, indexUnavailable {
                        Text("Couldn't load the Homebrew catalogue: \(error)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(recommended) { row(for: $0) }
                } header: {
                    if !recommended.isEmpty || model.isIndexLoading { Text("Recommended") }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(for package: Package) -> some View {
        Button {
            model.open(package.ref)
        } label: {
            PackageRow(package: package)
        }
        .buttonStyle(.rowButton)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            let count = model.outdated.count
            if count > 0 {
                Button(count == 1 ? "Upgrade 1 Package" : "Upgrade All (\(count))") {
                    model.perform(.upgradeAll(greedy: model.settings.includeAutoUpdatingCasks))
                }
                .disabled(!model.canPerformActions)
            } else {
                statusText
            }

            Spacer()

            if model.isCheckingForUpdates || model.isRefreshing {
                ProgressView().controlSize(.small)
            }

            Button {
                Task { await model.checkForUpdates(userInitiated: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Check for Updates")
            .disabled(model.isCheckingForUpdates || model.operation?.isRunning == true)
            .keyboardShortcut("r")

            Menu {
                Button("Settings…") { showSettings() }
                    .keyboardShortcut(",")
                Button("About Gingerbrew") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
                Divider()
                Button("Quit Gingerbrew") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusText: some View {
        if let last = model.settings.lastUpdateCheck {
            Text("Checked \(last, format: .relative(presentation: .named))")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if model.hasLoadedInstalled {
            Text(model.installed.count == 1 ? "1 package" : "\(model.installed.count) packages")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .lineLimit(3)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(10)
    }
}

/// A full-width list row that highlights on hover and press, like a menu item.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowButtonBody(configuration: configuration)
    }

    private struct RowButtonBody: View {
        let configuration: Configuration
        @ViewState private var isHovered = false

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : isHovered ? 0.06 : 0))
                )
                .padding(.horizontal, -6)
                .onHover { isHovered = $0 }
        }
    }
}

extension ButtonStyle where Self == RowButtonStyle {
    static var rowButton: RowButtonStyle { RowButtonStyle() }
}
