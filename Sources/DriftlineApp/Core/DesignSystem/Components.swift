import DriftlineCore
import SwiftUI

struct ConnectionStatusPill: View {
    var state: ConnectionState

    var body: some View {
        Label(self.label, systemImage: self.icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(self.color.opacity(0.16), in: Capsule())
            .foregroundStyle(self.color)
            .accessibilityLabel("Connection status: \(self.label)")
    }

    private var label: String {
        switch self.state {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .reconnecting: "Reconnecting"
        case .failed: "Failed"
        case .cancelling: "Cancelling"
        case .disconnected: "Disconnected"
        }
    }

    private var icon: String {
        switch self.state {
        case .connected: "checkmark.circle.fill"
        case .connecting, .reconnecting: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelling: "xmark.circle"
        case .disconnected: "circle"
        }
    }

    private var color: Color {
        switch self.state {
        case .connected: .green
        case .connecting, .reconnecting: .blue
        case .failed: .red
        case .cancelling: .orange
        case .disconnected: .secondary
        }
    }
}

struct TransferStatusBadge: View {
    var status: TransferStatus

    var body: some View {
        switch self.status {
        case .queued:
            Label("Queued", systemImage: "clock").foregroundStyle(.secondary)
        case let .running(progress, _):
            ProgressView(value: progress) {
                Text("\(Int(progress * 100))%")
            }
            .frame(width: 120)
        case .succeeded:
            Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled:
            Label("Cancelled", systemImage: "xmark.circle").foregroundStyle(.orange)
        }
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String?
    var systemImage: String

    init(title: String, message: String? = nil, systemImage: String) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }

    var body: some View {
        ContentUnavailableView(self.title, systemImage: self.systemImage, description: self.message.map(Text.init))
            .foregroundStyle(.primary.opacity(0.72))
    }
}

struct InspectorSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.title)
                .font(.headline)
            self.content
                .font(.callout)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
