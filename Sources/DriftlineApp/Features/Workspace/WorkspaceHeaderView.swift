import DriftlineCore
import SwiftUI

@MainActor
private func loc(_ key: String, _ args: CVarArg...) -> String {
    let format = LocalizationManager.shared.localized(key)
    if args.isEmpty { return format }
    return String(format: format, arguments: args)
}

/// Fork-inspired top workspace header.
///
/// Layer 1 pairs a grouped action rail with a centered current-session context block.
/// Layer 2 is a full-width workspace/session tab strip. The browser panes sit below.
struct WorkspaceHeaderView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            self.actionLayer
            Divider()
                .opacity(0.4)
            WorkspaceTabStrip(model: self.model)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(DriftlineOpacity.stroke))
                .frame(height: 1)
        }
    }

    private var actionLayer: some View {
        HStack(alignment: .center, spacing: 14) {
            self.leadingRail
            Spacer(minLength: 12)
            CurrentSessionContextView(model: self.model)
            Spacer(minLength: 12)
            self.trailingRail
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var leadingRail: some View {
        WorkspaceActionRail {
            WorkspaceActionButton(
                title: loc("sidebar.quickConnect"),
                systemImage: "bolt.horizontal",
                hint: loc("connection.newHint")
            ) {
                self.model.beginQuickConnect()
            }

            WorkspaceRailDivider()

            WorkspaceActionButton(
                title: loc("browser.refresh"),
                systemImage: "arrow.clockwise",
                hint: loc("browser.refreshHint")
            ) {
                Task { await self.model.refreshLocal() }
            }
            WorkspaceActionButton(
                title: loc("browser.refreshRemote"),
                systemImage: "globe",
                hint: loc("browser.refreshRemoteHint"),
                isDisabled: self.model.session.state != .connected
            ) {
                Task { await self.model.refreshRemote() }
            }

            WorkspaceRailDivider()

            WorkspaceActionButton(
                title: loc("browser.upload"),
                systemImage: "arrow.up",
                hint: loc("browser.uploadHint"),
                isDisabled: self.model.selectedLocalFiles.isEmpty || self.model.session.state != .connected
            ) {
                self.model.uploadSelectedItem()
            }
            WorkspaceActionButton(
                title: loc("browser.download"),
                systemImage: "arrow.down",
                hint: loc("browser.downloadHint"),
                isDisabled: self.model.selectedRemoteFiles.isEmpty || self.model.session.state != .connected
            ) {
                self.model.downloadSelectedItem()
            }
            WorkspaceActionButton(
                title: loc("browser.compare"),
                systemImage: "arrow.left.arrow.right",
                hint: loc("browser.compareHint"),
                isDisabled: self.model.session.state != .connected
            ) {
                self.model.prepareSyncPreview()
            }
        }
    }

    private var trailingRail: some View {
        WorkspaceActionRail {
            WorkspaceActionButton(
                title: loc("connection.terminal"),
                systemImage: "terminal",
                hint: loc("connection.terminalHint"),
                isDisabled: self.model.activeProfile == nil
            ) {
                self.model.openTerminalSession()
            }

            WorkspaceRailDivider()

            WorkspaceActionButton(
                title: loc("browser.newFolder"),
                systemImage: "folder.badge.plus"
            ) {
                self.model.beginCreateFolder(source: self.model.selectedFile?.source ?? .local)
            }
            WorkspaceActionButton(
                title: loc("browser.viewOptions"),
                systemImage: "slider.horizontal.3",
                isActive: self.model.showViewOptions
            ) {
                self.model.showViewOptions.toggle()
            }
            .popover(isPresented: self.$model.showViewOptions) {
                ViewOptionsView(preferences: self.$model.preferences) {
                    self.model.savePreferences()
                    Task {
                        await self.model.refreshLocal()
                        await self.model.refreshRemote()
                    }
                }
            }
            WorkspaceActionButton(
                title: loc("browser.inspector"),
                systemImage: "sidebar.right",
                isActive: self.model.preferences.showInspector
            ) {
                self.model.preferences.showInspector.toggle()
            }
        }
    }
}

/// Horizontal cluster of workspace actions with consistent spacing.
struct WorkspaceActionRail<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) {
            self.content
        }
    }
}

/// Subtle vertical separator used between action groups in a rail.
struct WorkspaceRailDivider: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 26)
            .padding(.horizontal, 4)
    }
}

/// macOS pro-app toolbar button: SF Symbol stacked over a compact label.
struct WorkspaceActionButton: View {
    var title: String
    var systemImage: String
    var hint: String?
    var isDisabled: Bool
    var isActive: Bool
    var action: () -> Void

    @State private var isHovering = false

    init(
        title: String,
        systemImage: String,
        hint: String? = nil,
        isDisabled: Bool = false,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.hint = hint
        self.isDisabled = isDisabled
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: self.action) {
            VStack(spacing: 3) {
                Image(systemName: self.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 18)
                Text(self.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(self.foreground)
            .frame(minWidth: 52)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(self.background)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(self.isDisabled)
        .onHover { self.isHovering = $0 && !self.isDisabled }
        .help(self.hint ?? self.title)
        .accessibilityLabel(self.title)
        .accessibilityHint(self.hint ?? "")
    }

    private var foreground: Color {
        if self.isDisabled { return .secondary.opacity(0.45) }
        if self.isActive { return .accentColor }
        return .primary.opacity(0.85)
    }

    private var background: Color {
        if self.isActive { return Color.accentColor.opacity(0.14) }
        if self.isHovering { return Color.primary.opacity(0.07) }
        return .clear
    }
}

/// Centered current-session context: server name, endpoint/protocol, status, and the
/// primary connection control. Anchors the top header visually.
struct CurrentSessionContextView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 3) {
            Text(self.primaryTitle)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            if let secondaryLine {
                Text(secondaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 5) {
                SessionStatusDot(state: self.model.session.state)
                Text(self.statusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            self.connectionControl
                .padding(.top, 3)
        }
        .frame(minWidth: 210)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var connectionControl: some View {
        if self.model.session.state == .connected {
            Button {
                self.model.disconnect()
            } label: {
                Label(loc("connection.disconnect"), systemImage: "xmark.circle")
            }
            .buttonStyle(GlassButtonStyle())
            .help(loc("connection.disconnectHint"))
            .accessibilityLabel(loc("connection.disconnect"))
        }
    }

    private var protocolLabel: String {
        self.model.session.protocolKind?.rawValue.uppercased() ?? "SFTP"
    }

    private var primaryTitle: String {
        self.model.activeProfile?.displayName ?? loc("app.name")
    }

    private var secondaryLine: String? {
        if self.model.session.state == .connected, let profile = self.model.activeProfile {
            return "\(self.protocolLabel) · \(profile.host):\(profile.port)"
        }
        if let profile = self.model.activeProfile {
            return profile.host
        }
        return loc("connection.noServer")
    }

    private var statusLine: String {
        if self.model.session.state == .connected {
            return loc("connection.connected")
        }
        return "\(self.protocolLabel) · \(self.model.session.state.localizedTitle)"
    }
}

/// Small status indicator shared by the context block and the tab items.
struct SessionStatusDot: View {
    var state: ConnectionState
    var size: CGFloat = 7

    @State private var isPulsing = false

    var body: some View {
        Group {
            switch self.state {
            case .connected:
                Circle().fill(.green)
            case .connecting, .reconnecting:
                Circle()
                    .fill(.blue)
                    .opacity(self.isPulsing ? 0.35 : 1)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            self.isPulsing = true
                        }
                    }
            case .failed:
                Circle().fill(.red)
            case .cancelling:
                Circle().fill(.orange)
            case .disconnected:
                Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1.2)
            }
        }
        .frame(width: self.size, height: self.size)
    }
}

/// Layer 2: full-width workspace/session tab strip with a trailing new-tab control.
struct WorkspaceTabStrip: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(self.model.tabs) { tab in
                WorkspaceTabItem(
                    title: tab.title,
                    state: tab.session.state,
                    isSelected: self.model.selectedTabID == tab.id,
                    showsClose: self.model.tabs.count > 1,
                    onSelect: { self.model.selectTab(tab.id) },
                    onClose: { self.model.requestCloseTab(tab.id) }
                )
            }
            Spacer(minLength: 8)
            WorkspaceNewTabButton {
                self.model.newTab()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

/// A single workspace/session tab with status dot, active/hover states, and optional close.
struct WorkspaceTabItem: View {
    var title: String
    var state: ConnectionState
    var isSelected: Bool
    var showsClose: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Button(action: self.onSelect) {
                HStack(spacing: 6) {
                    SessionStatusDot(state: self.state)
                    Text(self.title)
                        .font(.callout)
                        .fontWeight(self.isSelected ? .semibold : .regular)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if self.showsClose, self.isHovering || self.isSelected {
                Button(action: self.onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .contentShape(Circle())
                .accessibilityLabel(String(format: loc("tab.closeAction"), self.title))
            }
        }
        .foregroundStyle(self.isSelected ? .primary : .secondary)
        .padding(.leading, 11)
        .padding(.trailing, self.showsClose ? 7 : 11)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(self.isSelected ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(self.isHovering ? Color.primary.opacity(0.06) : Color.clear))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(self.isSelected ? DriftlineOpacity.stroke : 0), lineWidth: 1)
        }
        .onHover { self.isHovering = $0 }
    }
}

/// The "+" control that visually belongs to the tab strip; opens a new workspace tab.
struct WorkspaceNewTabButton: View {
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: self.action) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(self.isHovering ? .primary : .secondary)
                .frame(width: 28, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(self.isHovering ? Color.primary.opacity(0.07) : Color.clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { self.isHovering = $0 }
        .help(loc("menu.newTab"))
        .accessibilityLabel(loc("menu.newTab"))
    }
}
