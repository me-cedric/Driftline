import DriftlineCore
import SwiftUI

struct StatsDashboardView: View {
    var stats: TransferStats
    var lastConnection: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            self.fullStats
            self.compactStats
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var fullStats: some View {
        HStack(spacing: 12) {
            self.stat(LocalizationManager.shared.localized("stats.uploads"), "\(self.stats.uploadCount)", "arrow.up.circle")
            self.stat(LocalizationManager.shared.localized("stats.downloads"), "\(self.stats.downloadCount)", "arrow.down.circle")
            self.stat(LocalizationManager.shared.localized("stats.uploaded"), ByteCountFormatter.string(fromByteCount: self.stats.bytesUploaded), "externaldrive.badge.plus")
            self.stat(LocalizationManager.shared.localized("stats.downloaded"), ByteCountFormatter.string(fromByteCount: self.stats.bytesDownloaded), "externaldrive.badge.checkmark")
            self.stat(LocalizationManager.shared.localized("stats.active"), "\(self.stats.activeTransfers)", "bolt.circle")
            self.stat(LocalizationManager.shared.localized("stats.failed"), "\(self.stats.failedTransfers)", "exclamationmark.triangle")
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(LocalizationManager.shared.localized("stats.lastConnection"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(self.lastConnection)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        }
    }

    private var compactStats: some View {
        HStack(spacing: 12) {
            self.stat(LocalizationManager.shared.localized("stats.up"), "\(self.stats.uploadCount)", "arrow.up.circle")
            self.stat(LocalizationManager.shared.localized("stats.down"), "\(self.stats.downloadCount)", "arrow.down.circle")
            self.stat(LocalizationManager.shared.localized("stats.active"), "\(self.stats.activeTransfers)", "bolt.circle")
            self.stat(LocalizationManager.shared.localized("stats.failed"), "\(self.stats.failedTransfers)", "exclamationmark.triangle")
            Spacer()
            Text(self.lastConnection)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
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
