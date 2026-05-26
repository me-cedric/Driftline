import DriftlineCore
import SwiftUI

struct StatsDashboardView: View {
    var stats: TransferStats
    var lastConnection: String

    var body: some View {
        HStack(spacing: 12) {
            stat("Uploads", "\(stats.uploadCount)", "arrow.up.circle")
            stat("Downloads", "\(stats.downloadCount)", "arrow.down.circle")
            stat("Uploaded", ByteCountFormatter.string(fromByteCount: stats.bytesUploaded), "externaldrive.badge.plus")
            stat("Downloaded", ByteCountFormatter.string(fromByteCount: stats.bytesDownloaded), "externaldrive.badge.checkmark")
            stat("Active", "\(stats.activeTransfers)", "bolt.circle")
            stat("Failed", "\(stats.failedTransfers)", "exclamationmark.triangle")
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Last Connection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(lastConnection)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private func stat(_ label: String, _ value: String, _ icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
        .labelStyle(.titleAndIcon)
    }
}
