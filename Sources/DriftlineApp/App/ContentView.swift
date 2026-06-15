import DriftlineCore
import SwiftUI

@MainActor
private func loc(_ key: String, _ args: CVarArg...) -> String {
    let format = LocalizationManager.shared.localized(key)
    if args.isEmpty { return format }
    return String(format: format, arguments: args)
}

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var inspectorWidth: CGFloat = 280
    @State private var inspectorResizeStartWidth: CGFloat?
    @State private var transferHeight: CGFloat = 150
    @State private var transferResizeStartHeight: CGFloat?
    @State private var localPaneFraction: CGFloat = 0.5
    @State private var paneResizeStartWidth: CGFloat?
    private let inspectorChromeTopExtension: CGFloat = 24
    private static let paneDividerWidth: CGFloat = 9
    private static let paneMinWidth: CGFloat = 360

    var body: some View {
        ZStack(alignment: .trailing) {
            NavigationSplitView {
                SidebarView(model: self.model)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 360)
            } detail: {
                self.detailContent
            }
            if self.model.preferences.showInspector {
                self.inspectorOverlay
            }
        }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            WorkspaceHeaderView(model: self.model)
            if self.model.hasInitialLoadFailed {
                ContentUnavailableView(
                    loc("startup.failedTitle"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(self.model.session.lastErrorMessage.map { "\(loc("startup.failedDescription"))\n\($0)" } ?? loc("startup.failedDescription"))
                )
                .overlay(alignment: .bottom) {
                    Button {
                        self.model.retryInitialLoad()
                    } label: {
                        Label(loc("startup.retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 40)
                }
            } else {
                self.browserAndTransfers
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if let toast = model.statusMessage {
                    ToastOverlay(
                        message: toast.text,
                        systemImage: toast.systemImage,
                        iconColor: toast.iconColor
                    ) {
                        self.model.statusMessage = nil
                    }
                }
                if let message = model.footerMessage {
                    FooterBar(message: message) {
                        if self.model.footerMessage == message {
                            self.model.footerMessage = nil
                        }
                    }
                    .id(message)
                }
            }
        }
        .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
        .padding(.trailing, self.model.preferences.showInspector ? self.inspectorWidth + 1 : 0)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
        .sheet(item: self.$model.profileDraft) { draft in
            ServerProfileEditorView(
                draft: Binding(
                    get: { self.model.profileDraft ?? draft },
                    set: { self.model.profileDraft = $0 }
                ),
                savesAndConnects: self.model.connectAfterSavingDraft,
                errorMessage: self.model.profileEditorError,
                onCancel: {
                    self.model.profileDraft = nil
                    self.model.profileEditorError = nil
                    self.model.connectAfterSavingDraft = false
                },
                onSave: {
                    self.model.saveProfileDraft()
                }
            )
        }
        .sheet(item: self.$model.pendingHostTrust) { trust in
            HostTrustPromptView(
                trust: trust,
                onCancel: { self.model.pendingHostTrust = nil },
                onTrust: { self.model.trustPendingHostAndReconnect() }
            )
        }
        .sheet(item: self.$model.fileOperationPrompt) { prompt in
            FileOperationPromptView(
                title: prompt.title,
                text: self.$model.fileOperationText,
                onCancel: {
                    self.model.fileOperationPrompt = nil
                    self.model.fileOperationText = ""
                },
                onCommit: {
                    self.model.commitFileOperationPrompt()
                }
            )
        }
        .alert(loc("delete.title"), isPresented: Binding(
            get: { self.model.pendingDeleteItem != nil },
            set: { if !$0 { self.model.pendingDeleteItem = nil } }
        )) {
            Button(loc("delete.cancel"), role: .cancel) { self.model.pendingDeleteItem = nil }
            Button(loc("delete.delete"), role: .destructive) { self.model.deletePendingItem() }
        } message: {
            Text(self.model.pendingDeleteItem?.name ?? loc("delete.message"))
        }
        .sheet(item: self.$model.pendingTransferConflict) { conflict in
            TransferConflictView(
                conflict: conflict,
                renameText: self.$model.conflictRenameText,
                applyToRemaining: self.$model.conflictApplyToRemaining,
                remainingCount: self.model.queuedTransferConflicts.count,
                onSkip: { self.model.skipPendingConflict() },
                onOverwrite: { self.model.overwritePendingConflict() },
                onRename: { self.model.renameAndRunPendingConflict() }
            )
        }
        .sheet(item: self.$model.syncPreview) { preview in
            SyncPreviewView(
                preview: preview,
                onClose: { self.model.syncPreview = nil },
                onRunPlan: { self.model.runSyncPlan($0) }
            )
        }
        .alert(loc("update.available"), isPresented: Binding(
            get: { self.model.pendingUpdate != nil },
            set: { if !$0 { self.model.dismissPendingUpdate() } }
        )) {
            Button(loc("update.later"), role: .cancel) { self.model.dismissPendingUpdate() }
            Button(loc("update.download")) { self.model.openPendingUpdateDownload() }
        } message: {
            if let update = self.model.pendingUpdate {
                Text(String(format: loc("update.message"), update.latestVersion, update.currentVersion))
            }
        }
        .alert(
            self.model.userAlert?.title ?? "",
            isPresented: Binding(
                get: { self.model.userAlert != nil },
                set: { if !$0 { self.model.userAlert = nil } }
            )
        ) {
            Button(loc("alert.ok")) { self.model.userAlert = nil }
        } message: {
            if let alert = self.model.userAlert {
                Text(alert.message)
            }
        }
        .alert(loc("tab.closeTab"), isPresented: Binding(
            get: { self.model.pendingCloseTabID != nil },
            set: { if !$0 { self.model.cancelCloseTab() } }
        )) {
            Button(loc("tab.cancel"), role: .cancel) { self.model.cancelCloseTab() }
            Button(loc("tab.close"), role: .destructive) { self.model.confirmCloseTab() }
        } message: {
            if let tab = self.model.pendingCloseTab {
                let key = switch tab.session.state {
                case .connected: "tab.closeConfirm.connected"
                case .connecting: "tab.closeConfirm.connecting"
                case .reconnecting: "tab.closeConfirm.reconnecting"
                default: "tab.closeConfirm.default"
                }
                Text(String(format: loc(key), tab.title))
            }
        }
        .sheet(isPresented: self.$model.showAbout) {
            AboutView(
                isCheckingForUpdates: self.model.isCheckingForUpdates,
                onCheckForUpdates: { self.model.checkForUpdates(showNoUpdateMessage: true) },
                onRevealDiagnostics: { self.model.revealDiagnosticsLog() }
            )
        }
    }

    private var inspectorOverlay: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1)
                .overlay {
                    Rectangle()
                        .fill(.clear)
                        .frame(width: 8)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    let startWidth = self.inspectorResizeStartWidth ?? self.inspectorWidth
                                    self.inspectorResizeStartWidth = startWidth
                                    self.inspectorWidth = min(420, max(240, startWidth - value.translation.width))
                                }
                                .onEnded { _ in
                                    self.inspectorResizeStartWidth = nil
                                }
                        )
                }
            InspectorView(
                file: self.model.selectedFile,
                session: self.model.session,
                profile: self.model.activeProfile,
                transferStats: self.model.transferStats,
                lastConnection: self.model.lastConnectionDisplay
            )
            .frame(width: self.inspectorWidth)
            .padding(.top, self.inspectorChromeTopExtension)
            .background(.ultraThinMaterial)
        }
        .frame(maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    private var browserAndTransfers: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                self.fileBrowserSplit
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                if self.model.preferences.showTransferQueue {
                    PaneSplitHandle()
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    let start = self.transferResizeStartHeight ?? self.transferHeight
                                    self.transferResizeStartHeight = start
                                    let maxHeight = max(160, proxy.size.height - 320)
                                    self.transferHeight = min(maxHeight, max(120, start - value.translation.height))
                                }
                                .onEnded { _ in self.transferResizeStartHeight = nil }
                        )
                    self.transferQueue
                        .frame(height: self.transferHeight)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var fileBrowserSplit: some View {
        GeometryReader { proxy in
            let available = max(0, proxy.size.width - Self.paneDividerWidth)
            let localWidth = self.localPaneWidth(available: available)
            HStack(spacing: 0) {
                FileBrowserPane(
                    title: loc("browser.local"),
                    path: self.model.session.localPath,
                    items: self.model.localItems,
                    source: .local,
                    selectionIDs: self.$model.selectedLocalFileIDs,
                    onSelectionChange: { self.model.selectItems($0, in: .local) },
                    onOpen: { self.model.navigateLocal(to: $0) },
                    onNavigate: { self.model.navigateLocal(toPath: $0) },
                    onParent: { self.model.navigateLocalParent() },
                    onRefresh: { Task { await self.model.refreshLocal() } },
                    onCreateFolder: { self.model.beginCreateFolder(source: .local) },
                    onRename: { self.model.beginRenameSelectedItem(source: .local) },
                    onDelete: { self.model.requestDeleteSelectedItem(source: .local) },
                    onTransfer: { items in
                        if self.model.session.state == .connected {
                            self.model.uploadItems(items)
                        } else {
                            if let item = items.first {
                                self.model.navigateLocal(to: item)
                            }
                        }
                    },
                    onDropItems: { self.model.transferDroppedItems($0, to: .local) },
                    onCopy: { self.model.copyItems($0) },
                    onPaste: { self.model.pasteCopiedItems(into: .local) },
                    onShowInfo: {
                        self.model.activePane = .local
                        self.model.preferences.showInspector = true
                    },
                    loadChildren: { item, completion in self.model.loadChildren(of: item, completion: completion) }
                )
                .frame(width: localWidth)
                PaneVerticalDivider()
                    .frame(width: Self.paneDividerWidth)
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                let start = self.paneResizeStartWidth ?? localWidth
                                self.paneResizeStartWidth = start
                                guard available > 0 else { return }
                                self.localPaneFraction = min(1, max(0, (start + value.translation.width) / available))
                            }
                            .onEnded { _ in self.paneResizeStartWidth = nil }
                    )
                FileBrowserPane(
                    title: loc("browser.remote"),
                    path: self.model.session.remotePath,
                    items: self.model.remoteItems,
                    source: .remote,
                    isConnected: self.model.session.state == .connected,
                    selectionIDs: self.$model.selectedRemoteFileIDs,
                    onSelectionChange: { self.model.selectItems($0, in: .remote) },
                    onOpen: { self.model.navigateRemote(to: $0) },
                    onNavigate: { self.model.navigateRemote(toPath: $0) },
                    onParent: { self.model.navigateRemoteParent() },
                    onRefresh: { Task { await self.model.refreshRemote() } },
                    onCreateFolder: { self.model.beginCreateFolder(source: .remote) },
                    onRename: { self.model.beginRenameSelectedItem(source: .remote) },
                    onDelete: { self.model.requestDeleteSelectedItem(source: .remote) },
                    onTransfer: { self.model.downloadItems($0) },
                    onDropItems: { self.model.transferDroppedItems($0, to: .remote) },
                    onCopy: { self.model.copyItems($0) },
                    onPaste: { self.model.pasteCopiedItems(into: .remote) },
                    onShowInfo: {
                        self.model.activePane = .remote
                        self.model.preferences.showInspector = true
                    },
                    onNewConnection: { self.model.beginQuickConnect() },
                    loadChildren: { item, completion in self.model.loadChildren(of: item, completion: completion) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func localPaneWidth(available: CGFloat) -> CGFloat {
        guard available > 0 else { return 0 }
        guard available > Self.paneMinWidth * 2 else { return available / 2 }
        let ideal = available * self.localPaneFraction
        return min(max(ideal, Self.paneMinWidth), available - Self.paneMinWidth)
    }

    private var transferQueue: some View {
        TransferPanel(
            jobs: self.model.transferJobs,
            lastConnection: self.model.lastConnectionDisplay,
            onClearCompleted: { self.model.clearCompletedTransfers() },
            onClearFailed: { self.model.clearFailedTransfers() },
            onRetryFailed: { self.model.retryFailedTransfers() },
            onCancelActive: { self.model.cancelActiveTransfers() },
            onCancelTransfer: { self.model.cancelTransfer(id: $0) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SidebarSection(title: loc("sidebar.driftline")) {
                    SidebarNavRow(
                        title: loc("sidebar.newConnection"),
                        systemImage: "plus",
                        isSelected: false,
                        isPrimary: true
                    ) {
                        self.model.beginQuickConnect()
                    }
                }
                SidebarSection(title: loc("sidebar.favorites"), systemImage: "star") {
                    let favorites = self.model.profiles.filter(\.isFavorite)
                    if favorites.isEmpty {
                        SidebarEmptyRow(loc("sidebar.markFavorites"))
                    } else {
                        ForEach(favorites) { profile in
                            SidebarNavRow(
                                title: profile.displayName,
                                subtitle: self.profileSubtitle(profile),
                                systemImage: "star.fill",
                                isSelected: self.isSelected(profile),
                                statusColor: self.statusColor(for: profile)
                            ) {
                                self.model.selectedSidebarItem = self.sidebarID(for: profile)
                                self.model.connectToSelectedServer()
                            }
                            .contextMenu {
                                Button(loc("sidebar.contextConnect")) {
                                    self.model.selectedSidebarItem = self.sidebarID(for: profile)
                                    self.model.connectToSelectedServer()
                                }
                                Button(loc("sidebar.contextEdit")) {
                                    self.model.selectedSidebarItem = self.sidebarID(for: profile)
                                    self.model.beginEditingSelectedProfile()
                                }
                                Button(loc("menu.duplicate")) {
                                    self.model.selectedSidebarItem = self.sidebarID(for: profile)
                                    self.model.duplicateSelectedProfile()
                                }
                                Divider()
                                Button(loc("menu.delete"), role: .destructive) {
                                    self.model.selectedSidebarItem = self.sidebarID(for: profile)
                                    self.model.deleteSelectedProfile()
                                }
                            }
                        }
                    }
                }
                SidebarSection(title: loc("sidebar.savedServers"), systemImage: "server.rack") {
                    if self.model.profiles.isEmpty {
                        SidebarEmptyRow(loc("sidebar.noSavedServers"))
                    } else {
                        ForEach(self.model.profiles) { profile in
                            SidebarNavRow(
                                title: profile.displayName,
                                subtitle: self.profileSubtitle(profile),
                                systemImage: "network",
                                isSelected: self.isSelected(profile),
                                statusColor: self.statusColor(for: profile)
                            ) {
                                self.model.selectedSidebarItem = self.sidebarID(for: profile)
                                self.model.connectToSelectedServer()
                            }
                            .contextMenu {
                                Button(loc("sidebar.contextConnect")) {
                                    self.model.selectedSidebarItem = self.sidebarID(for: profile)
                                    self.model.connectToSelectedServer()
                                }
                                Button(loc("sidebar.contextEdit")) {
                                    self.model.selectedSidebarItem = self.sidebarID(for: profile)
                                    self.model.beginEditingSelectedProfile()
                                }
                                Button(loc("menu.duplicate")) {
                                    self.model.selectedSidebarItem = self.sidebarID(for: profile)
                                    self.model.duplicateSelectedProfile()
                                }
                                Divider()
                                Button(loc("menu.delete"), role: .destructive) {
                                    self.model.selectedSidebarItem = self.sidebarID(for: profile)
                                    self.model.deleteSelectedProfile()
                                }
                            }
                        }
                    }
                }
                SidebarSection(title: loc("sidebar.bookmarks"), systemImage: "bookmark") {
                    if self.model.bookmarks.isEmpty {
                        SidebarEmptyRow(loc("sidebar.noBookmarks"), detail: loc("sidebar.noBookmarksDetail"))
                    } else {
                        ForEach(self.model.bookmarks) { bookmark in
                            SidebarNavRow(
                                title: bookmark.name,
                                systemImage: "bookmark",
                                isSelected: false
                            ) {
                                self.model.openBookmark(bookmark)
                            }
                        }
                    }
                }
                SidebarSection(title: loc("sidebar.recent"), systemImage: "clock") {
                    if self.model.recents.isEmpty {
                        SidebarEmptyRow(loc("sidebar.noRecent"))
                    } else {
                        ForEach(self.model.recents) { recent in
                            SidebarNavRow(
                                title: recent.displayName,
                                subtitle: self.recentSubtitle(recent),
                                systemImage: "clock",
                                isSelected: false
                            ) {
                                self.model.openRecent(recent)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 14)
        }
        .navigationTitle(loc("app.name"))
    }

    private func sidebarID(for profile: ServerProfile) -> String {
        profile.id.rawValue.uuidString
    }

    private func isSelected(_ profile: ServerProfile) -> Bool {
        self.model.selectedSidebarItem == self.sidebarID(for: profile)
    }

    private func profileSubtitle(_ profile: ServerProfile) -> String {
        "\(profile.protocolKind.rawValue.uppercased()) · \(profile.host)"
    }

    private func recentSubtitle(_ recent: RecentServer) -> String {
        recent.connectedAt.formatted(date: .omitted, time: .shortened)
    }

    private func statusColor(for profile: ServerProfile) -> Color {
        guard self.model.activeProfile?.id == profile.id else { return .secondary.opacity(0.58) }
        switch self.model.session.state {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .blue
        case .failed:
            return .red
        case .cancelling:
            return .orange
        case .disconnected:
            return .secondary.opacity(0.58)
        }
    }
}

struct SidebarSection<Content: View>: View {
    var title: String
    var systemImage: String?
    @ViewBuilder var content: Content

    init(title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.semibold))
                        .frame(width: 13)
                }
                Text(self.title)
                    .lineLimit(1)
                Spacer()
            }
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary.opacity(0.78))
            .padding(.horizontal, 11)
            self.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SidebarNavRow: View {
    var title: String
    var subtitle: String?
    var systemImage: String
    var isSelected: Bool
    var isPrimary: Bool
    var statusColor: Color?
    var action: () -> Void

    @State private var isHovering = false

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        isSelected: Bool,
        isPrimary: Bool = false,
        statusColor: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.isPrimary = isPrimary
        self.statusColor = statusColor
        self.action = action
    }

    var body: some View {
        Button {
            self.action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: self.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(self.iconColor)
                    .frame(width: 22, alignment: .center)
                VStack(alignment: .leading, spacing: 1) {
                    Text(self.title)
                        .font(.body.weight((self.isSelected || self.isPrimary) ? .semibold : .regular))
                        .foregroundStyle(self.titleColor)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let statusColor {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .overlay {
                            Circle()
                                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                        }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, self.subtitle == nil ? 7 : 7)
            .frame(maxWidth: .infinity, minHeight: self.subtitle == nil ? 34 : 44, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(self.backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.accentColor.opacity(self.isSelected ? 0.16 : 0), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { self.isHovering = $0 }
    }

    private var backgroundColor: Color {
        if self.isPrimary {
            return Color.accentColor.opacity(self.isHovering ? 0.88 : 0.96)
        }
        if self.isSelected {
            return Color.accentColor.opacity(0.12)
        }
        if self.isHovering {
            return Color.primary.opacity(0.055)
        }
        return .clear
    }

    private var iconColor: Color {
        if self.isPrimary {
            return .white
        }
        return self.isSelected ? Color.accentColor : Color.primary.opacity(0.74)
    }

    private var titleColor: Color {
        if self.isPrimary {
            return .white
        }
        return self.isSelected ? Color.accentColor : Color.primary
    }
}

struct SidebarEmptyRow: View {
    var text: String
    var detail: String?

    init(_ text: String, detail: String? = nil) {
        self.text = text
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(self.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.025))
        }
    }
}
