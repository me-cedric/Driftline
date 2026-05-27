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
            TextField("Name", text: self.$text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(self.onCommit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: self.onCancel)
                Button("Save", action: self.onCommit)
                    .buttonStyle(.borderedProminent)
                    .disabled(self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
