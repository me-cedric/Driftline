import SwiftUI

struct FileOperationPromptView: View {
    var title: String
    @Binding var text: String
    var onCancel: () -> Void
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())
            TextField("Name", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onCommit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save", action: onCommit)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
