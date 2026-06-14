import DriftlineCore
import SwiftUI

@MainActor
private func loc(_ key: String) -> String {
    LocalizationManager.shared.localized(key)
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var selectedLanguage: SupportedLanguage = .english
    @State private var refreshID = UUID()

    var body: some View {
        TabView {
            SettingsGeneralPane(
                preferences: self.$model.preferences,
                selectedLanguage: self.$selectedLanguage
            )
            .onAppear { self.selectedLanguage = self.model.preferences.localizedLanguage }
            .onChange(of: self.selectedLanguage) { _, newValue in
                self.model.setLanguage(newValue)
                self.refreshID = UUID()
            }
            .tabItem {
                Label(loc("settings.general"), systemImage: "gearshape")
            }

            SettingsAppearancePane(preferences: self.$model.preferences)
                .tabItem {
                    Label(loc("settings.appearance"), systemImage: "paintpalette")
                }

            SettingsBehaviorPane(preferences: self.$model.preferences)
                .tabItem {
                    Label(loc("settings.behavior"), systemImage: "switch.2")
                }

            AppAboutContent(
                isCheckingForUpdates: self.model.isCheckingForUpdates,
                onCheckForUpdates: { self.model.checkForUpdates(showNoUpdateMessage: true) },
                onRevealDiagnostics: { self.model.revealDiagnosticsLog() }
            )
            .tabItem {
                Label(loc("settings.about"), systemImage: "info.circle")
            }
        }
        .id(self.refreshID)
        .padding(20)
        .frame(width: 500, height: 460)
    }
}

// MARK: - General Pane

private struct SettingsGeneralPane: View {
    @Binding var preferences: ViewPreferences
    @Binding var selectedLanguage: SupportedLanguage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(title: loc("settings.language")) {
                    Picker(selection: self.$selectedLanguage) {
                        ForEach(SupportedLanguage.allCases) { language in
                            HStack(spacing: 6) {
                                Text(language.flag)
                                Text(language.displayName)
                            }
                            .tag(language)
                        }
                    } label: {
                        Label(loc("settings.languagePicker"), systemImage: "globe")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 240)
                }

                SettingsSection(title: loc("settings.browser")) {
                    Toggle(loc("settings.showHiddenFiles"), isOn: self.$preferences.fileList.showHiddenFiles)
                    Toggle(loc("settings.showFileExtensions"), isOn: self.$preferences.fileList.showFileExtensions)
                    Toggle(loc("settings.foldersFirst"), isOn: self.$preferences.fileList.foldersFirst)

                    HStack(spacing: 12) {
                        Picker(loc("settings.sortBy"), selection: self.$preferences.fileList.sortKey) {
                            ForEach(FileSortKey.allCases, id: \.self) { key in
                                Text(key.localizedTitle).tag(key)
                            }
                        }
                        .frame(width: 140)

                        Toggle(loc("settings.ascending"), isOn: self.$preferences.fileList.sortAscending)
                    }
                }

                SettingsSection(title: loc("settings.panels")) {
                    Toggle(loc("settings.showSidebar"), isOn: self.$preferences.showSidebar)
                    Toggle(loc("settings.showInspector"), isOn: self.$preferences.showInspector)
                    Toggle(loc("settings.showTransferQueue"), isOn: self.$preferences.showTransferQueue)
                }
            }
            .padding(.top, 12)
        }
    }
}

// MARK: - Appearance Pane

private struct SettingsAppearancePane: View {
    @Binding var preferences: ViewPreferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(title: loc("settings.appIcon")) {
                    Picker(loc("settings.appIcon"), selection: self.$preferences.appIconVariant) {
                        ForEach(AppIconVariant.allCases) { variant in
                            Text(variant.displayName).tag(variant)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }

                SettingsSection(title: loc("settings.theme")) {
                    Picker(loc("settings.theme"), selection: self.$preferences.appThemeVariant) {
                        ForEach(AppThemeVariant.allCases) { variant in
                            Text(variant.displayName).tag(variant)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }
            }
            .padding(.top, 12)
        }
    }
}

// MARK: - Behavior Pane

private struct SettingsBehaviorPane: View {
    @Binding var preferences: ViewPreferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(title: loc("settings.notifications")) {
                    Toggle(loc("settings.confirmBeforeDelete"), isOn: self.$preferences.confirmBeforeDelete)
                    Toggle(loc("settings.confirmBeforeOverwrite"), isOn: self.$preferences.confirmBeforeOverwrite)
                    Toggle(loc("settings.checkUpdatesOnStartup"), isOn: self.$preferences.checkForUpdatesOnStartup)
                    Toggle(loc("settings.backgroundNotifications"), isOn: self.$preferences.backgroundNotificationsEnabled)
                }

                SettingsSection(title: loc("settings.transfers")) {
                    HStack(spacing: 12) {
                        Text(loc("settings.transferConcurrency"))
                            .frame(width: 130, alignment: .leading)
                        Stepper("\(self.preferences.transferConcurrency)", value: self.$preferences.transferConcurrency, in: 1 ... 8)
                    }
                }

                SettingsSection(title: loc("settings.remoteBackend")) {
                    Picker(loc("settings.remoteBackend"), selection: self.$preferences.remoteBackendKind) {
                        ForEach(RemoteBackendKind.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Text(self.preferences.remoteBackendKind == .nativeSwiftExperimental
                        ? loc("settings.backend.native")
                        : loc("settings.backend.system"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 12)
        }
    }
}

// MARK: - Shared Components

private struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(self.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                self.content
            }
            .padding(12)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
