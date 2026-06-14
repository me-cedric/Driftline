import DriftlineCore
import SwiftUI

struct FileOperationPromptView: View {
    var title: String
    @Binding var text: String
    var onCancel: () -> Void
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(self.title)
                .font(.title2.bold())
            TextField(LocalizationManager.shared.localized("fileOperation.name"), text: self.$text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(self.onCommit)
            HStack {
                Spacer()
                Button(LocalizationManager.shared.localized("fileOperation.cancel"), role: .cancel, action: self.onCancel)
                Button(LocalizationManager.shared.localized("fileOperation.save"), action: self.onCommit)
                    .buttonStyle(.borderedProminent)
                    .disabled(self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
