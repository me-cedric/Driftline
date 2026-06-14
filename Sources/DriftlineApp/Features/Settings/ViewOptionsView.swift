import DriftlineCore
import SwiftUI

struct ViewOptionsView: View {
    @Binding var preferences: ViewPreferences
    var onChange: () -> Void

    var body: some View {
        Form {
            Section(LocalizationManager.shared.localized("viewOptions.browser")) {
                Toggle(LocalizationManager.shared.localized("settings.showHiddenFiles"), isOn: self.$preferences.fileList.showHiddenFiles)
                Toggle(LocalizationManager.shared.localized("settings.showFileExtensions"), isOn: self.$preferences.fileList.showFileExtensions)
                Toggle(LocalizationManager.shared.localized("settings.foldersFirst"), isOn: self.$preferences.fileList.foldersFirst)
                Picker(LocalizationManager.shared.localized("settings.sortBy"), selection: self.$preferences.fileList.sortKey) {
                    ForEach(FileSortKey.allCases, id: \.self) { key in
                        Text(key.localizedTitle).tag(key)
                    }
                }
                Toggle(LocalizationManager.shared.localized("settings.ascending"), isOn: self.$preferences.fileList.sortAscending)
            }

            Section(LocalizationManager.shared.localized("viewOptions.panels")) {
                Toggle(LocalizationManager.shared.localized("settings.showSidebar"), isOn: self.$preferences.showSidebar)
                Toggle(LocalizationManager.shared.localized("settings.showInspector"), isOn: self.$preferences.showInspector)
                Toggle(LocalizationManager.shared.localized("settings.showTransferQueue"), isOn: self.$preferences.showTransferQueue)
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
