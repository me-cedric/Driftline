import DriftlineCore
import SwiftUI

struct HostTrustPromptView: View {
    var trust: PendingHostTrust
    var onCancel: () -> Void
    var onTrust: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(LocalizationManager.shared.localized("trust.title"), systemImage: "lock.shield")
                .font(.title2.bold())
            Text("\(self.trust.host):\(self.trust.port)")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizationManager.shared.localized("trust.algorithm"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(self.trust.algorithm)
                Text(LocalizationManager.shared.localized("trust.fingerprint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(self.trust.fingerprint)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            Text(LocalizationManager.shared.localized("trust.warning"))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(LocalizationManager.shared.localized("delete.cancel"), role: .cancel, action: self.onCancel)
                Button(LocalizationManager.shared.localized("trust.trustAndConnect"), action: self.onTrust)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(LocalizationManager.shared.localized("trust.hint"))
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
