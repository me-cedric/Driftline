import DriftlineCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            SettingsGeneralPane(preferences: self.$model.preferences)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AppAboutContent(
                isCheckingForUpdates: self.model.isCheckingForUpdates,
                onCheckForUpdates: { self.model.checkForUpdates(showNoUpdateMessage: true) },
                onRevealDiagnostics: { self.model.revealDiagnosticsLog() }
            )
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .padding(20)
        .frame(width: 460, height: 430)
    }
}

private struct SettingsGeneralPane: View {
    @Binding var preferences: ViewPreferences

    var body: some View {
        Form {
            Toggle("Show hidden files", isOn: self.$preferences.fileList.showHiddenFiles)
            Toggle("Confirm before delete", isOn: self.$preferences.confirmBeforeDelete)
            Toggle("Confirm before overwrite", isOn: self.$preferences.confirmBeforeOverwrite)
            Toggle("Check for updates on startup", isOn: self.$preferences.checkForUpdatesOnStartup)
            Toggle("Background notifications", isOn: self.$preferences.backgroundNotificationsEnabled)
            Stepper("Transfer concurrency: \(self.preferences.transferConcurrency)", value: self.$preferences.transferConcurrency, in: 1 ... 8)
            Picker("Remote backend", selection: self.$preferences.remoteBackendKind) {
                ForEach(RemoteBackendKind.allCases) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            Text(self.preferences.remoteBackendKind == .nativeSwiftExperimental
                ? "Experimental: native SFTP supports password and private-key workflows; use System SSH for SSH agent auth."
                : "Recommended: uses macOS SSH shell tools with strict host verification, SSH agent support, and rsync transfers.")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.68))
            Picker("App icon", selection: self.$preferences.appIconVariant) {
                ForEach(AppIconVariant.allCases) { variant in
                    Text(variant.displayName).tag(variant)
                }
            }
            .pickerStyle(.segmented)
            Picker("Theme", selection: self.$preferences.appThemeVariant) {
                ForEach(AppThemeVariant.allCases) { variant in
                    Text(variant.displayName).tag(variant)
                }
            }
            .pickerStyle(.segmented)
            Picker("Default sort", selection: self.$preferences.fileList.sortKey) {
                ForEach(FileSortKey.allCases, id: \.self) { key in
                    Text(key.rawValue.capitalized).tag(key)
                }
            }
        }
        .padding(.top, 12)
    }
}
