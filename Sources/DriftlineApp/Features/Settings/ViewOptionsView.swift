import DriftlineCore
import SwiftUI

struct ViewOptionsView: View {
    @Binding var preferences: ViewPreferences
    var onChange: () -> Void

    var body: some View {
        Form {
            Section("Browser") {
                Toggle("Show hidden files", isOn: self.$preferences.fileList.showHiddenFiles)
                Toggle("Show file extensions", isOn: self.$preferences.fileList.showFileExtensions)
                Toggle("Folders first", isOn: self.$preferences.fileList.foldersFirst)
                Picker("Sort by", selection: self.$preferences.fileList.sortKey) {
                    ForEach(FileSortKey.allCases, id: \.self) { key in
                        Text(key.rawValue.capitalized).tag(key)
                    }
                }
                Toggle("Ascending", isOn: self.$preferences.fileList.sortAscending)
            }

            Section("Panels") {
                Toggle("Show sidebar", isOn: self.$preferences.showSidebar)
                Toggle("Show inspector", isOn: self.$preferences.showInspector)
                Toggle("Show transfer queue", isOn: self.$preferences.showTransferQueue)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 320)
        .onChange(of: self.preferences) { _, _ in
            self.onChange()
        }
    }
}
