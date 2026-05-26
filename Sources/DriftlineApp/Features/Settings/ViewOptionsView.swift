import DriftlineCore
import SwiftUI

struct ViewOptionsView: View {
    @Binding var preferences: ViewPreferences
    var onChange: () -> Void

    var body: some View {
        Form {
            Section("Browser") {
                Toggle("Show hidden files", isOn: $preferences.fileList.showHiddenFiles)
                Toggle("Show file extensions", isOn: $preferences.fileList.showFileExtensions)
                Toggle("Folders first", isOn: $preferences.fileList.foldersFirst)
                Picker("Sort by", selection: $preferences.fileList.sortKey) {
                    ForEach(FileSortKey.allCases, id: \.self) { key in
                        Text(key.rawValue.capitalized).tag(key)
                    }
                }
                Toggle("Ascending", isOn: $preferences.fileList.sortAscending)
            }

            Section("Panels") {
                Toggle("Show sidebar", isOn: $preferences.showSidebar)
                Toggle("Show inspector", isOn: $preferences.showInspector)
                Toggle("Show transfer queue", isOn: $preferences.showTransferQueue)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 320)
        .onChange(of: preferences) { _, _ in
            onChange()
        }
    }
}
