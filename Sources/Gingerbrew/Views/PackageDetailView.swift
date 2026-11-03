import AppKit
import GingerbrewCore
import SwiftUI

struct PackageDetailView: View {
    let ref: PackageRef
    @Environment(AppModel.self) private var model
    @ViewState private var pendingRemoval: PackageAction?

    var body: some View {
        let package = model.package(for: ref)
        VStack(spacing: 0) {
            navigationBar(package)
            Divider()
            if let package {
                content(package)
            } else if let error = model.detailErrors[ref] {
                ContentUnavailableView {
                    Label("Couldn't Load \(ref.shortName)", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await model.loadDetail(ref) }
    }

    // MARK: Navigation bar

    private func navigationBar(_ package: Package?) -> some View {
        HStack(spacing: 10) {
            Button {
                model.goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back (⌘[)")

            Spacer()

            if let package, let appURL = PackageMetadata.appURL(for: package) {
                Button {
                    NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Open \(package.displayName)")
            }
            if let homepage = package?.homepage {
                Link(destination: homepage) {
                    Image(systemName: "safari")
                }
                .buttonStyle(.borderless)
                .help("Open Website")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: Content

    private func content(_ package: Package) -> some View {
        Form {
            Section {
                information(package)
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    header(package)
                    if let pendingRemoval {
                        RemovalConfirmation(
                            package: package,
                            action: pendingRemoval,
                            dependents: model.usedBy(package),
                            confirm: {
                                model.perform(pendingRemoval)
                                self.pendingRemoval = nil
                            },
                            cancel: { self.pendingRemoval = nil })
                    } else {
                        actions(package)
                    }
                    if let operation = model.operation {
                        OperationStatusView(operation: operation)
                    }
                }
                .padding(.bottom, 6)
            }

            if let caveats = package.caveats {
                Section("Caveats") {
                    Text(caveats)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            dependencies(package)

            if package.isInstalled {
                usedBy(package)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func header(_ package: Package) -> some View {
        HStack(alignment: .center, spacing: 12) {
            PackageIcon(package: package, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(package.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                if let summary = package.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if package.displayName != package.name {
                    Text(package.name)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .textCase(nil)
    }

    @ViewBuilder
    private func actions(_ package: Package) -> some View {
        HStack(spacing: 8) {
            if !package.isInstalled {
                Button("Install") { model.perform(.install(package.ref)) }
                    .buttonStyle(.borderedProminent)
                    .disabled(package.isDisabled)
            } else {
                if package.isOutdated {
                    Button("Upgrade to \(package.latestVersion ?? "Latest")") {
                        model.perform(.upgrade(package.ref))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(package.isPinned)
                    .help(package.isPinned ? "Pinned packages aren't upgraded. Run `brew unpin \(package.name)` first." : "")
                }
                Menu("Uninstall…") {
                    Button("Uninstall…") { pendingRemoval = .uninstall(package.ref) }
                    Button("Remove Completely…") { pendingRemoval = .uninstallCompletely(package.ref) }
                } primaryAction: {
                    pendingRemoval = .uninstall(package.ref)
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .disabled(!model.canPerformActions)
        .textCase(nil)
    }

    // MARK: Sections

    @ViewBuilder
    private func information(_ package: Package) -> some View {
        LabeledContent("Version") {
            if package.isOutdated, let installed = package.installedVersion {
                Text("\(installed) → \(package.latestVersion ?? "?")")
            } else {
                Text(package.installedVersion ?? package.latestVersion ?? "—")
            }
        }
        .monospacedDigit()

        if let developer = PackageMetadata.developer(for: package) {
            LabeledContent("Developer", value: developer)
        }

        LabeledContent("Type", value: package.kind == .cask ? "App (cask)" : "Command-line tool (formula)")

        if let tap = package.tap {
            LabeledContent("Source", value: tap)
        }
        if let license = package.license {
            LabeledContent("License", value: license)
        }
        if let date = package.installedDate {
            LabeledContent("Installed") {
                Text(date, format: .dateTime.year().month().day())
            }
        }
        if package.isInstalled, package.kind == .formula, !package.installedOnRequest {
            LabeledContent("Installed As", value: "Dependency")
        }
        if package.installedVersions.count > 1 {
            LabeledContent("Versions Kept", value: package.installedVersions.joined(separator: ", "))
        }
        if package.autoUpdates {
            LabeledContent("Updates", value: "Updates itself")
        }
        if package.isPinned {
            LabeledContent("Pinned", value: "Won't be upgraded")
        }
        if package.isDeprecated || package.isDisabled {
            Label(
                package.isDisabled ? "Disabled in Homebrew" : "Deprecated in Homebrew",
                systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        if let homepage = package.homepage {
            LabeledContent("Website") {
                Link(homepage.host ?? homepage.absoluteString, destination: homepage)
            }
        }
        if let appURL = PackageMetadata.appURL(for: package) {
            LabeledContent("Location") {
                Button(appURL.deletingLastPathComponent().path) {
                    NSWorkspace.shared.activateFileViewerSelecting([appURL])
                }
                .buttonStyle(.link)
                .help("Show in Finder")
            }
        }
    }

    @ViewBuilder
    private func dependencies(_ package: Package) -> some View {
        Section {
            if package.dependencies.isEmpty {
                if model.loadingDetails.contains(ref) {
                    ProgressView().controlSize(.small)
                } else {
                    Text("No dependencies").foregroundStyle(.secondary)
                }
            } else {
                ForEach(package.dependencies, id: \.self) { dependency in
                    DependencyRow(ref: dependency, installed: model.installedPackage(for: dependency)) {
                        model.open(dependency)
                    }
                }
            }
        } header: {
            Text("Depends On")
        } footer: {
            if !package.dependencies.isEmpty {
                let missing = package.dependencies.filter { model.installedPackage(for: $0) == nil }.count
                if !package.isInstalled, missing > 0 {
                    Text("\(missing) of these will be installed too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func usedBy(_ package: Package) -> some View {
        let dependents = model.usedBy(package)
        Section("Used By") {
            if dependents.isEmpty {
                Text("Nothing else depends on it").foregroundStyle(.secondary)
            } else {
                ForEach(dependents) { dependent in
                    DependencyRow(ref: dependent.ref, installed: dependent) {
                        model.open(dependent.ref)
                    }
                }
            }
        }
    }
}

struct DependencyRow: View {
    let ref: PackageRef
    let installed: Package?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack {
                Text(installed?.displayName ?? ref.shortName)
                    .foregroundStyle(.primary)
                if ref.kind == .cask {
                    Text("App")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let installed {
                    if installed.isOutdated {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.tint)
                    }
                    Text(installed.installedVersion ?? "")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not installed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows details")
    }
}

/// Inline confirmation for uninstalling, instead of an alert (which would close the panel).
struct RemovalConfirmation: View {
    let package: Package
    let action: PackageAction
    let dependents: [Package]
    let confirm: () -> Void
    let cancel: () -> Void

    private var isComplete: Bool {
        if case .uninstallCompletely = action { return true }
        return false
    }

    private var explanation: String {
        switch (package.kind, isComplete) {
        case (.cask, false):
            "Removes the app. Its settings and support files stay on your Mac."
        case (.cask, true):
            "Removes the app and deletes its settings, caches and support files (brew uninstall --zap). This can't be undone."
        case (.formula, false):
            "Removes \(package.name) \(package.installedVersion ?? "")."
        case (.formula, true):
            package.installedVersions.count > 1
                ? "Removes all \(package.installedVersions.count) installed versions of \(package.name)."
                : "Removes \(package.name) and any older versions Homebrew kept."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isComplete ? "Remove \(package.displayName) completely?" : "Uninstall \(package.displayName)?")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !dependents.isEmpty {
                Label {
                    Text("Required by \(dependents.map(\.displayName).formatted(.list(type: .and))). Homebrew won't remove it while they're installed.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(isComplete ? "Remove Completely" : "Uninstall", role: .destructive, action: confirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .textCase(nil)
    }
}
