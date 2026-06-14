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
            .accessibilityLabel("\(String(format: LocalizationManager.shared.localized("connection.connectionStatus"), self.label))")
    }

    private var label: String {
        switch self.state {
        case .connected: LocalizationManager.shared.localized("connection.connected")
        case .connecting: LocalizationManager.shared.localized("connection.connecting")
        case .reconnecting: LocalizationManager.shared.localized("connection.reconnecting")
        case .failed: LocalizationManager.shared.localized("connection.failed")
        case .cancelling: LocalizationManager.shared.localized("connection.cancelling")
        case .disconnected: LocalizationManager.shared.localized("connection.disconnected")
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
            Label(LocalizationManager.shared.localized("transfer.queued"), systemImage: "clock").foregroundStyle(.secondary)
        case let .running(progress, _):
            ProgressView(value: progress) {
                Text("\(Int(progress * 100))%")
            }
            .frame(width: 120)
        case .succeeded:
            Label(LocalizationManager.shared.localized("transfer.done"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Label(LocalizationManager.shared.localized("transfer.failed"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled:
            Label(LocalizationManager.shared.localized("transfer.cancelled"), systemImage: "xmark.circle").foregroundStyle(.orange)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ToastOverlay: View {
    var message: String
    var systemImage = "checkmark.circle.fill"
    var iconColor: Color = .green
    var onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: self.systemImage)
                .foregroundStyle(self.iconColor)
            Text(self.message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button(action: self.onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .scaleEffect(self.isVisible ? 1 : 0.9, anchor: .bottom)
        .opacity(self.isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                self.isVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.onDismiss()
                }
            }
        }
    }
}

struct FooterBar: View {
    var message: String
    var onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(self.message)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button(action: self.onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(.bar)
        .opacity(self.isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                self.isVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.onDismiss()
                }
            }
        }
    }
}
