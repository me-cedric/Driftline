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
            Label(LocalizationManager.shared.localized("conflict.title"), systemImage: "exclamationmark.triangle")
                .font(.title2.bold())
            Text(LocalizationManager.shared.localized("conflict.existsAt"))
                .foregroundStyle(.secondary)
            Text(self.conflict.existingPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(LocalizationManager.shared.localized("conflict.existingDestination"))
                .accessibilityValue(self.conflict.existingPath)

            TextField(LocalizationManager.shared.localized("conflict.renameDestination"), text: self.$renameText)
                .textFieldStyle(.roundedBorder)
                .accessibilityHint(LocalizationManager.shared.localized("conflict.renameHint"))

            if self.remainingCount > 0 {
                Toggle(self.remainingCount == 1
                    ? String(format: LocalizationManager.shared.localized("conflict.applySingle"), self.remainingCount)
                    : String(format: LocalizationManager.shared.localized("conflict.applyPlural"), self.remainingCount), isOn: self.$applyToRemaining)
                    .accessibilityHint(LocalizationManager.shared.localized("conflict.applyHint"))
            }

            HStack {
                Button(LocalizationManager.shared.localized("conflict.skip"), role: .cancel, action: self.onSkip)
                    .help(self.applyToRemaining ? LocalizationManager.shared.localized("conflict.skipHelpMulti") : LocalizationManager.shared.localized("conflict.skipHelpSingle"))
                    .accessibilityHint(LocalizationManager.shared.localized("conflict.skipHint"))
                Spacer()
                Button(LocalizationManager.shared.localized("conflict.overwrite"), role: .destructive, action: self.onOverwrite)
                    .help(self.applyToRemaining ? LocalizationManager.shared.localized("conflict.overwriteHelpMulti") : LocalizationManager.shared.localized("conflict.overwriteHelpSingle"))
                    .accessibilityHint(LocalizationManager.shared.localized("conflict.overwriteHint"))
                Button(LocalizationManager.shared.localized("conflict.transferRenamed"), action: self.onRename)
                    .buttonStyle(.borderedProminent)
                    .disabled(self.renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(LocalizationManager.shared.localized("conflict.renameHelp"))
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
