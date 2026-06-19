import DriftlineCore
import SwiftUI

struct TransferPanel: View {
    var jobs: [TransferJob]
    var lastConnection: String
    var onClearCompleted: () -> Void
    var onClearFailed: () -> Void
    var onRetryFailed: () -> Void
    var onCancelActive: () -> Void
    var onCancelTransfer: (TransferJobID) -> Void

    @State private var filter: TransferFilter = .all
    @State private var sortOrder = [KeyPathComparator(\TransferJob.createdAt, order: .reverse)]

    private var activeCount: Int {
        self.jobs.filter(\.isActive).count
    }

    private var failedCount: Int {
        self.jobs.filter(\.isFailed).count
    }

    private var completedCount: Int {
        self.jobs.filter(\.isCompleted).count
    }

    private var filteredJobs: [TransferJob] {
        switch self.filter {
        case .all:
            self.jobs
        case .active:
            self.jobs.filter(\.isActive)
        case .failed:
            self.jobs.filter(\.isFailed)
        case .completed:
            self.jobs.filter(\.isCompleted)
        }
    }

    private var sortedJobs: [TransferJob] {
        self.filteredJobs.sorted(using: self.sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            self.header
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            Divider()
                .opacity(0.12)
            self.content
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DriftlineRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DriftlineRadius.card, style: .continuous)
                .stroke(Color.primary.opacity(DriftlineOpacity.separator), lineWidth: 1)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                self.titleBlock
                self.filterPicker
                Spacer()
                self.actions
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    self.titleBlock
                    Spacer()
                    self.actions
                }
                self.filterPicker
            }
        }
    }

    private var titleBlock: some View {
        HStack(spacing: 8) {
            Label(LocalizationManager.shared.localized("transfer.transfers"), systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
            Text("· \(self.activeCount) \(LocalizationManager.shared.localized("stats.active").lowercased()) · \(self.failedCount) \(LocalizationManager.shared.localized("stats.failed").lowercased()) · \(self.completedCount) \(LocalizationManager.shared.localized("transfer.completed").lowercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var filterPicker: some View {
        Picker(LocalizationManager.shared.localized("transfer.filter"), selection: self.$filter) {
            ForEach(TransferFilter.allCases) { filter in
                Text(filter.localizedTitle)
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 280)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if self.activeCount > 0 {
                Button(LocalizationManager.shared.localized("transfer.cancelActive"), action: self.onCancelActive)
                    .accessibilityHint(LocalizationManager.shared.localized("transfer.cancelsActiveHint"))
            }
            if self.failedCount > 0 {
                Button(LocalizationManager.shared.localized("transfer.retryFailed"), action: self.onRetryFailed)
                    .accessibilityHint(LocalizationManager.shared.localized("transfer.retriesFailedHint"))
                Button(LocalizationManager.shared.localized("transfer.clearFailed"), action: self.onClearFailed)
            }
            if self.completedCount > 0 {
                Button(LocalizationManager.shared.localized("transfer.clearCompleted"), action: self.onClearCompleted)
            }
        }
        .buttonStyle(GlassButtonStyle())
    }

    @ViewBuilder
    private var content: some View {
        if self.jobs.isEmpty {
            VStack(spacing: 4) {
                Text(LocalizationManager.shared.localized("transfer.noTransfers"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(LocalizationManager.shared.localized("transfer.emptyMessage"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(String(format: LocalizationManager.shared.localized("stats.lastConnectionFormat"), self.lastConnection))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 14)
        } else {
            Table(self.sortedJobs, sortOrder: self.$sortOrder) {
                TableColumn(LocalizationManager.shared.localized("transfer.column.status"), value: \.statusSortValue) { job in
                    TransferStatusBadge(status: job.status)
                }
                .width(min: 90, ideal: 120, max: 150)
                TableColumn(LocalizationManager.shared.localized("transfer.column.progress"), value: \.progressSortValue) { job in
                    TransferProgressCell(job: job)
                }
                .width(min: 120, ideal: 150, max: 190)
                TableColumn(LocalizationManager.shared.localized("transfer.column.direction"), value: \.directionSortValue) { job in
                    Label(job.direction.localizedTitle, systemImage: job.direction == .upload ? "arrow.up.circle" : "arrow.down.circle")
                }
                .width(min: 92, ideal: 120, max: 150)
                TableColumn(LocalizationManager.shared.localized("transfer.column.source"), value: \.sourcePath) { job in
                    Text(job.sourcePath)
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.78))
                }
                .width(min: 120, ideal: 220)
                TableColumn(LocalizationManager.shared.localized("transfer.column.destination"), value: \.destinationPath) { job in
                    Text(job.destinationPath)
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.78))
                }
                .width(min: 120, ideal: 220)
                TableColumn(LocalizationManager.shared.localized("transfer.column.server"), value: \.serverSortValue) { job in
                    Text(job.serverName ?? "--")
                        .foregroundStyle(.primary.opacity(0.72))
                }
                .width(min: 80, ideal: 120, max: 180)
                TableColumn(LocalizationManager.shared.localized("transfer.column.action")) { job in
                    Button {
                        self.onCancelTransfer(job.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!job.isCancellable)
                    .help(LocalizationManager.shared.localized("transfer.cancelTransfer"))
                    .accessibilityLabel(LocalizationManager.shared.localized("transfer.cancelTransferAccessibility"))
                }
            }
            .overlay {
                if self.sortedJobs.isEmpty {
                    EmptyStateView(
                        title: LocalizationManager.shared.localized("transfer.noFilteredTransfers"),
                        message: LocalizationManager.shared.localized("transfer.noFilteredTransfersMessage"),
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
            }
        }
    }
}

private enum TransferFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case failed
    case completed

    var id: String {
        self.rawValue
    }

    var localizedTitle: String {
        switch self {
        case .all:
            LocalizationManager.shared.localized("transfer.filter.all")
        case .active:
            LocalizationManager.shared.localized("transfer.filter.active")
        case .failed:
            LocalizationManager.shared.localized("transfer.filter.failed")
        case .completed:
            LocalizationManager.shared.localized("transfer.filter.completed")
        }
    }
}

private struct TransferProgressCell: View {
    var job: TransferJob

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: self.progress)
                .progressViewStyle(.linear)
                .frame(minWidth: 70)
            Text(self.progress.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
            if let speed = self.speed {
                Text(ByteCountFormatter.string(fromByteCount: speed) + "/s")
                    .lineLimit(1)
                    .frame(minWidth: 58, alignment: .leading)
            }
            if let eta = self.eta {
                Text(String(format: LocalizationManager.shared.localized("transfer.eta"), eta))
                    .lineLimit(1)
                    .frame(minWidth: 56, alignment: .leading)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var progress: Double {
        switch self.job.status {
        case let .running(progress, _):
            min(max(progress, 0), 1)
        case .succeeded:
            1
        default:
            0
        }
    }

    private var speed: Int64? {
        if case let .running(_, bytesPerSecond) = self.job.status {
            return bytesPerSecond
        }
        return nil
    }

    private var eta: String? {
        guard let seconds = self.job.estimatedRemainingSeconds else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds)
    }
}

private extension TransferJob {
    var isActive: Bool {
        switch status {
        case .queued, .running:
            true
        case .succeeded, .failed, .cancelled:
            false
        }
    }

    var isCancellable: Bool {
        switch status {
        case .queued, .running:
            true
        case .succeeded, .failed, .cancelled:
            false
        }
    }

    var isCompleted: Bool {
        if case .succeeded = status {
            return true
        }
        return false
    }

    var isFailed: Bool {
        if case .failed = status {
            return true
        }
        return false
    }

    var statusSortValue: String {
        switch self.status {
        case .queued:
            "0-queued"
        case .running:
            "1-running"
        case .failed:
            "2-failed"
        case .cancelled:
            "3-cancelled"
        case .succeeded:
            "4-succeeded"
        }
    }

    var progressSortValue: Double {
        switch self.status {
        case let .running(progress, _):
            progress
        case .succeeded:
            1
        default:
            0
        }
    }

    var directionSortValue: String {
        self.direction.rawValue
    }

    var serverSortValue: String {
        self.serverName ?? ""
    }
}
