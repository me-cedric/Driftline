import DriftlineCore
import SwiftUI

struct TransferPanel: View {
    var jobs: [TransferJob]
    var onClearCompleted: () -> Void
    var onClearFailed: () -> Void
    var onRetryFailed: () -> Void
    var onCancelActive: () -> Void
    var onCancelTransfer: (TransferJobID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                self.fullHeader
                self.compactHeader
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)

            Table(self.jobs) {
                TableColumn("Status") { job in
                    TransferStatusBadge(status: job.status)
                }
                .width(min: 90, ideal: 120, max: 150)
                TableColumn("Direction") { job in
                    Label(job.direction.rawValue.capitalized, systemImage: job.direction == .upload ? "arrow.up.circle" : "arrow.down.circle")
                }
                .width(min: 92, ideal: 120, max: 150)
                TableColumn("Source") { job in
                    Text(job.sourcePath)
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.78))
                }
                .width(min: 120, ideal: 220)
                TableColumn("Destination") { job in
                    Text(job.destinationPath)
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.78))
                }
                .width(min: 120, ideal: 220)
                TableColumn("Server") { job in
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

private extension TransferJob {
    var isCancellable: Bool {
        switch status {
        case .queued, .running:
            true
        case .succeeded, .failed, .cancelled:
            false
        }
    }
}
