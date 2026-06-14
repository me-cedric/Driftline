import DriftlineCore
import SwiftUI

struct TransferPanel: View {
    var jobs: [TransferJob]
    var onClearCompleted: () -> Void
    var onClearFailed: () -> Void
    var onRetryFailed: () -> Void
    var onCancelActive: () -> Void
    var onCancelTransfer: (TransferJobID) -> Void

    @State private var sortOrder = [KeyPathComparator(\TransferJob.createdAt, order: .reverse)]

    private var sortedJobs: [TransferJob] {
        self.jobs.sorted(using: self.sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                self.fullHeader
                self.compactHeader
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)

            Table(self.sortedJobs, sortOrder: self.$sortOrder) {
                TableColumn("Status", value: \.statusSortValue) { job in
                    TransferStatusBadge(status: job.status)
                }
                .width(min: 90, ideal: 120, max: 150)
                TableColumn("Progress", value: \.progressSortValue) { job in
                    TransferProgressCell(job: job)
                }
                .width(min: 120, ideal: 150, max: 190)
                TableColumn("Direction", value: \.directionSortValue) { job in
                    Label(job.direction.rawValue.capitalized, systemImage: job.direction == .upload ? "arrow.up.circle" : "arrow.down.circle")
                }
                .width(min: 92, ideal: 120, max: 150)
                TableColumn("Source", value: \.sourcePath) { job in
                    Text(job.sourcePath)
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.78))
                }
                .width(min: 120, ideal: 220)
                TableColumn("Destination", value: \.destinationPath) { job in
                    Text(job.destinationPath)
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.78))
                }
                .width(min: 120, ideal: 220)
                TableColumn("Server", value: \.serverSortValue) { job in
                    Text(job.serverName ?? "--")
                        .foregroundStyle(.primary.opacity(0.72))
                }
                .width(min: 80, ideal: 120, max: 180)
                TableColumn("Action") { job in
                    Button {
                        self.onCancelTransfer(job.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!job.isCancellable)
                    .help("Cancel Transfer")
                    .accessibilityLabel("Cancel transfer")
                }
            }
            .overlay {
                if self.jobs.isEmpty {
                    EmptyStateView(
                        title: "No Transfers Yet",
                        message: "Uploads and downloads will appear here with progress, retries, and history.",
                        systemImage: "arrow.up.arrow.down.circle"
                    )
                }
            }
        }
        .background(.regularMaterial)
    }

    private var fullHeader: some View {
        HStack {
            Label("Transfers", systemImage: "arrow.up.arrow.down")
                .font(.headline)
            Spacer()
            Button("Cancel Active", action: self.onCancelActive)
                .accessibilityHint("Cancels active transfers.")
            Button("Retry Failed", action: self.onRetryFailed)
                .accessibilityHint("Retries failed transfers.")
            Button("Clear Failed", action: self.onClearFailed)
            Button("Clear Completed", action: self.onClearCompleted)
        }
    }

    private var compactHeader: some View {
        HStack {
            Label("Transfers", systemImage: "arrow.up.arrow.down")
                .font(.headline)
            Spacer()
            Button(action: self.onCancelActive) {
                Image(systemName: "xmark.circle")
            }
            .help("Cancel Active")
            Button(action: self.onRetryFailed) {
                Image(systemName: "arrow.clockwise.circle")
            }
            .help("Retry Failed")
            Button(action: self.onClearFailed) {
                Image(systemName: "exclamationmark.triangle")
            }
            .help("Clear Failed")
            Button(action: self.onClearCompleted) {
                Image(systemName: "checkmark.circle")
            }
            .help("Clear Completed")
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
}

private extension TransferJob {
    var isCancellable: Bool {
        switch status {
        case .queued, .running:
            true
        case .succeeded, .failed, .cancelled:
            false
        }
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
