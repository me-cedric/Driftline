import AppKit
import DriftlineCore
import SwiftUI

enum DriftlineRadius {
    static let window: CGFloat = 20
    static let panel: CGFloat = 16
    static let card: CGFloat = 14
    static let control: CGFloat = 10
    static let pill: CGFloat = 999
}

enum DriftlineSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum DriftlineOpacity {
    static let hover = 0.06
    static let selected = 0.14
    static let separator = 0.04
    static let stroke = 0.065
}

extension View {
    /// The system Liquid Glass button on macOS 26 and later, the previous capsule style before.
    @ViewBuilder
    func driftlineGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(GlassButtonStyle(isPrimary: prominent))
        }
    }

    /// Liquid Glass for a control that floats over content, such as a toast. A material before macOS 26.
    @ViewBuilder
    func driftlineFloatingGlass(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        }
    }

    /// Groups nearby glass buttons so they share one glass layer and blend when close (macOS 26 and later).
    @ViewBuilder
    func driftlineGlassGroup(spacing: CGFloat = 6) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

/// The separator between the file panes and the transfer queue, with a resize cursor and a 7 pt drag target.
struct PaneSplitHandle: View {
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: self.isHovering ? 2 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: 7)
            // The drag target matches the panes, so no window background shows between them.
            .background(Color(nsColor: .controlBackgroundColor))
            .contentShape(Rectangle())
            .onHover { hovering in
                self.isHovering = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

/// A subtle, glass-compatible vertical divider for resizing side-by-side panes.
/// Renders a low-opacity hairline that brightens on hover/drag and adopts a
/// horizontal-resize cursor, replacing the harsh native split divider while
/// preserving a comfortable drag hit target.
struct PaneVerticalDivider: View {
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(self.isHovering ? Color.primary.opacity(0.16) : Color(nsColor: .separatorColor))
                .frame(width: self.isHovering ? 2 : 1)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            self.isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

/// The pre-macOS 26 look of `driftlineGlassButton()`. Use the modifier, not this style.
struct GlassButtonStyle: ButtonStyle {
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(self.isPrimary ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(self.fill(isPressed: configuration.isPressed))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(self.isPrimary ? 0 : DriftlineOpacity.stroke), lineWidth: 1)
            }
    }

    private func fill(isPressed: Bool) -> Color {
        if self.isPrimary {
            return Color.accentColor.opacity(isPressed ? 0.82 : 0.98)
        }
        return Color.primary.opacity(isPressed ? 0.14 : 0.08)
    }
}

struct ConnectionStatusPill: View {
    var state: ConnectionState

    var body: some View {
        Label(self.label, systemImage: self.icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(self.color.opacity(0.28), lineWidth: 1)
            }
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
        case .running:
            // The Progress column shows the bar and the numbers; the status stays one short line.
            Label(LocalizationManager.shared.localized("transfer.running"), systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
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
        VStack(alignment: .leading, spacing: 12) {
            Text(self.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.9))
            self.content
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // The inspector column draws its own background; a fill groups the rows without stacking materials.
        .background(.quinary, in: RoundedRectangle(cornerRadius: DriftlineRadius.card, style: .continuous))
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
        .driftlineFloatingGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
