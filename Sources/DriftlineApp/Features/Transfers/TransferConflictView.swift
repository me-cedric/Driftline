import DriftlineCore
import SwiftUI

struct TransferConflictView: View {
    var conflict: TransferConflict
    @Binding var renameText: String
    var onSkip: () -> Void
    var onOverwrite: () -> Void
    var onRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Transfer Conflict", systemImage: "exclamationmark.triangle")
                .font(.title2.bold())
            Text("An item already exists at:")
                .foregroundStyle(.secondary)
            Text(conflict.existingPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            TextField("Rename destination", text: $renameText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Skip", role: .cancel, action: onSkip)
                Spacer()
                Button("Overwrite", role: .destructive, action: onOverwrite)
                    .accessibilityHint("Starts the transfer and replaces the existing destination item.")
                Button("Transfer as Rename", action: onRename)
                    .buttonStyle(.borderedProminent)
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
