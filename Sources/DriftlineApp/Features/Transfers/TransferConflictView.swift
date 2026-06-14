import DriftlineCore
import SwiftUI

struct TransferConflictView: View {
    var conflict: TransferConflict
    @Binding var renameText: String
    @Binding var applyToRemaining: Bool
    var remainingCount: Int
    var onSkip: () -> Void
    var onOverwrite: () -> Void
    var onRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Transfer Conflict", systemImage: "exclamationmark.triangle")
                .font(.title2.bold())
            Text("An item already exists at:")
                .foregroundStyle(.secondary)
            Text(self.conflict.existingPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Existing destination")
                .accessibilityValue(self.conflict.existingPath)

            TextField("Rename destination", text: self.$renameText)
                .textFieldStyle(.roundedBorder)
                .accessibilityHint("Enter a new destination filename for this transfer only.")

            if self.remainingCount > 0 {
                Toggle("Apply Skip or Overwrite to \(self.remainingCount) remaining conflict\(self.remainingCount == 1 ? "" : "s")", isOn: self.$applyToRemaining)
                    .accessibilityHint("Rename always applies only to the current conflict.")
            }

            HStack {
                Button("Skip", role: .cancel, action: self.onSkip)
                    .help(self.applyToRemaining ? "Skip this and all remaining conflicts." : "Skip this transfer.")
                    .accessibilityHint("Leaves the existing item unchanged.")
                Spacer()
                Button("Overwrite", role: .destructive, action: self.onOverwrite)
                    .help(self.applyToRemaining ? "Overwrite this and all remaining conflicts." : "Overwrite this destination.")
                    .accessibilityHint("Starts the transfer and replaces the existing destination item.")
                Button("Transfer as Renamed", action: self.onRename)
                    .buttonStyle(.borderedProminent)
                    .disabled(self.renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Transfer this item using the rename field.")
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
