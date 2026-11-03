import GingerbrewCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var launchAtLogin = LoginItem.isEnabled
    @ViewState private var loginError: String?

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .disabled(!LoginItem.isAvailable)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Picker("Check for updates", selection: $settings.checkIntervalHours) {
                    ForEach(AppSettings.intervalChoices, id: \.self) { hours in
                        Text(hours == 1 ? "Every hour" : "Every \(hours) hours").tag(hours)
                    }
                    Divider()
                    Text("Never").tag(0)
                }
                Toggle(isOn: $settings.includeAutoUpdatingCasks) {
                    Text("Include apps that update themselves")
                    Text("Shows updates for casks like browsers that normally update on their own.")
                }
                .onChange(of: settings.includeAutoUpdatingCasks) {
                    Task { await model.refresh() }
                }
                Toggle("Show notifications", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled { Notifier.requestAuthorization() }
                    }
                LabeledContent("Last checked") {
                    HStack {
                        if model.isCheckingForUpdates {
                            ProgressView().controlSize(.small)
                        } else if let last = settings.lastUpdateCheck {
                            Text(last, format: .relative(presentation: .named))
                        } else {
                            Text("Never")
                        }
                        Button("Check Now") {
                            Task { await model.checkForUpdates(userInitiated: true) }
                        }
                        .disabled(model.isCheckingForUpdates)
                    }
                }
            } header: {
                Text("Updates")
            }

            Section {
                LabeledContent("Catalogue") {
                    HStack {
                        if model.isIndexLoading {
                            ProgressView().controlSize(.small)
                        } else if let updated = model.indexUpdatedAt {
                            Text("Updated \(updated, format: .relative(presentation: .named))")
                        } else {
                            Text("Not downloaded")
                        }
                        Button("Refresh") {
                            Task { await model.prepareIndex(force: true) }
                        }
                        .disabled(model.isIndexLoading)
                    }
                }
                if let error = model.indexError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Search")
            } footer: {
                Text("Search results for packages you don't have come from formulae.brew.sh and refresh daily.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent("Homebrew", value: model.brewVersion ?? "—")
                LabeledContent("Location", value: model.service?.prefix ?? "Not found")
                LabeledContent("Gingerbrew", value: Bundle.main.shortVersion)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }
}
