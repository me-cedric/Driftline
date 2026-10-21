import DriftlineCore
import SwiftUI

@MainActor
private func loc(_ key: String, _ args: CVarArg...) -> String {
    let format = LocalizationManager.shared.localized(key)
    if args.isEmpty { return format }
    return String(format: format, arguments: args)
}

/// The workspace header below the window toolbar: the session tab strip.
/// The actions live in the system toolbar (`WorkspaceToolbar`), which draws Liquid Glass on macOS 26 and later.
struct WorkspaceHeaderView: View {
    @Bindable var model: AppModel

    var body: some View {
        WorkspaceTabStrip(model: self.model)
    }
}

/// The window toolbar. Each group becomes one glass capsule on macOS 26 and later; the system also handles
/// overflow, the icon and label display modes, and keyboard focus.
struct WorkspaceToolbar: ToolbarContent {
    @Bindable var model: AppModel

    private var isConnected: Bool {
        self.model.session.state == .connected
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                self.model.beginQuickConnect()
            } label: {
                Label(loc("sidebar.quickConnect"), systemImage: "bolt.horizontal")
            }
            .help(loc("connection.newHint"))
        }

        ToolbarItemGroup(placement: .primaryAction) {
            self.connectionButton
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                self.model.uploadSelectedItem()
            } label: {
                Label(loc("browser.upload"), systemImage: "arrow.up")
            }
            .help(loc("browser.uploadHint"))
            .disabled(self.model.selectedLocalFiles.isEmpty || !self.isConnected)

            Button {
                self.model.downloadSelectedItem()
            } label: {
                Label(loc("browser.download"), systemImage: "arrow.down")
            }
            .help(loc("browser.downloadHint"))
            .disabled(self.model.selectedRemoteFiles.isEmpty || !self.isConnected)

            Button {
                self.model.prepareSyncPreview()
            } label: {
                Label(loc("browser.compare"), systemImage: "arrow.left.arrow.right")
            }
            .help(loc("browser.compareHint"))
            .disabled(!self.isConnected)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task {
                    await self.model.refreshLocal()
                    await self.model.refreshRemote()
                }
            } label: {
                Label(loc("browser.refresh"), systemImage: "arrow.clockwise")
            }
            .help(loc("browser.refreshHint"))

            Button {
                self.model.beginCreateFolder(source: self.model.selectedFile?.source ?? .local)
            } label: {
                Label(loc("browser.newFolder"), systemImage: "folder.badge.plus")
            }

            Button {
                self.model.openTerminalSession()
            } label: {
                Label(loc("connection.terminal"), systemImage: "terminal")
            }
            .help(loc("connection.terminalHint"))
            .disabled(self.model.activeProfile == nil)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                self.model.showViewOptions.toggle()
            } label: {
                Label(loc("browser.viewOptions"), systemImage: "slider.horizontal.3")
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

            Toggle(isOn: self.$model.preferences.showInspector) {
                Label(loc("browser.inspector"), systemImage: "sidebar.right")
            }
            .help(loc("browser.inspector"))
        }
    }

    @ViewBuilder private var connectionButton: some View {
        if self.isConnected {
            Button {
                self.model.disconnect()
            } label: {
                Label(loc("connection.disconnect"), systemImage: "xmark.circle")
            }
            .help(loc("connection.disconnectHint"))
        } else if self.model.activeProfile != nil, self.model.session.state != .connecting, self.model.session.state != .reconnecting {
            // The one tinted control: connecting is the next step on this screen.
            Button {
                self.model.connectToSelectedServer()
            } label: {
                Label(loc("connection.connect"), systemImage: "arrow.triangle.2.circlepath")
            }
            .help(loc("connection.connectHint"))
            .driftlineGlassButton(prominent: true)
        } else if self.model.session.state == .connecting || self.model.session.state == .reconnecting {
            ProgressView()
                .controlSize(.small)
                .help(self.model.session.state.localizedTitle)
        }
    }
}

extension AppModel {
    /// Window title for the current session: the server name, or the app name.
    var workspaceTitle: String {
        self.activeProfile?.displayName ?? loc("app.name")
    }

    /// Window subtitle: protocol, endpoint and state, for example "SFTP · public.cgi.com:22 · Connected".
    var workspaceSubtitle: String {
        guard let profile = self.activeProfile else { return loc("connection.noServer") }
        let protocolLabel = (self.session.protocolKind ?? profile.protocolKind).rawValue.uppercased()
        return "\(protocolLabel) · \(profile.host):\(profile.port) · \(self.session.state.localizedTitle)"
    }
}

/// Small status indicator for the tab items.
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
            // A fill, not a material: the strip sits on content, under the glass toolbar.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(self.isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(self.isHovering ? Color.primary.opacity(0.06) : Color.clear))
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
