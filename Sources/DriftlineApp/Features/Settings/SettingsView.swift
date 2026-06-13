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
                ? "Experimental: native SFTP supports password and private-key workflows; use System SSH for SSH agent auth."
                : "Recommended: uses macOS SSH shell tools with strict host verification, SSH agent support, and rsync transfers.")
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
