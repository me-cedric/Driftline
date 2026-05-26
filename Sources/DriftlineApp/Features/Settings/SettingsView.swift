import DriftlineCore
import SwiftUI

struct SettingsView: View {
    @Binding var preferences: ViewPreferences

    var body: some View {
        Form {
            Toggle("Show hidden files", isOn: $preferences.fileList.showHiddenFiles)
            Toggle("Confirm before delete", isOn: $preferences.confirmBeforeDelete)
            Toggle("Confirm before overwrite", isOn: $preferences.confirmBeforeOverwrite)
            Stepper("Transfer concurrency: \(preferences.transferConcurrency)", value: $preferences.transferConcurrency, in: 1...8)
            Picker("Remote backend", selection: $preferences.remoteBackendKind) {
                ForEach(RemoteBackendKind.allCases) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            Text(preferences.remoteBackendKind == .nativeSwiftExperimental
                 ? "Experimental: credentials are read from Keychain through the native Swift path, but SFTP file operations remain guarded until the subsystem is complete."
                 : "Recommended: uses macOS system SSH tools with strict host verification.")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.68))
            Picker("Default sort", selection: $preferences.fileList.sortKey) {
                ForEach(FileSortKey.allCases, id: \.self) { key in
                    Text(key.rawValue.capitalized).tag(key)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
