import DriftlineCore
import SwiftUI

struct SettingsView: View {
    @Binding var preferences: ViewPreferences

    var body: some View {
        Form {
            Toggle("Show hidden files", isOn: self.$preferences.fileList.showHiddenFiles)
            Toggle("Confirm before delete", isOn: self.$preferences.confirmBeforeDelete)
            Toggle("Confirm before overwrite", isOn: self.$preferences.confirmBeforeOverwrite)
            Stepper("Transfer concurrency: \(self.preferences.transferConcurrency)", value: self.$preferences.transferConcurrency, in: 1 ... 8)
            Picker("Remote backend", selection: self.$preferences.remoteBackendKind) {
                ForEach(RemoteBackendKind.allCases) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            Text(self.preferences.remoteBackendKind == .nativeSwiftExperimental
                ? "Experimental: credentials are read from Keychain through the native Swift path, but SFTP file operations remain guarded until the subsystem is complete."
                : "Recommended: uses macOS system SSH tools with strict host verification.")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.68))
            Picker("Default sort", selection: self.$preferences.fileList.sortKey) {
                ForEach(FileSortKey.allCases, id: \.self) { key in
                    Text(key.rawValue.capitalized).tag(key)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
