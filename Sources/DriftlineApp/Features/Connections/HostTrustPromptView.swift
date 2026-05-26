import SwiftUI

struct HostTrustPromptView: View {
    var trust: PendingHostTrust
    var onCancel: () -> Void
    var onTrust: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Trust Host?", systemImage: "lock.shield")
                .font(.title2.bold())
            Text("\(trust.host):\(trust.port)")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text("Algorithm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(trust.algorithm)
                Text("Fingerprint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(trust.fingerprint)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            Text("Only trust this host if the fingerprint matches a value you verified out of band.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Trust and Connect", action: onTrust)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Stores this fingerprint in Driftline known hosts and reconnects.")
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
