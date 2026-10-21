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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var transferHeight: CGFloat = 150
    @State private var transferResizeStartHeight: CGFloat?
    @State private var localPaneFraction: CGFloat = 0.5
    @State private var paneResizeStartWidth: CGFloat?
    private static let paneDividerWidth: CGFloat = 9
    private static let paneMinWidth: CGFloat = 360

    var body: some View {
        NavigationSplitView {
            SidebarView(model: self.model)
                .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 360)
        } detail: {
            self.detailContent
                .navigationTitle(self.model.workspaceTitle)
                .navigationSubtitle(self.model.workspaceSubtitle)
                .toolbar {
                    WorkspaceToolbar(model: self.model)
                }
                // One search field in the toolbar, like Finder. It filters the pane that has the focus.
                .searchable(text: self.activeFilterText, placement: .toolbar, prompt: Text(self.filterPrompt))
                // The system inspector column: its own background, resize handle and window integration.
                .inspector(isPresented: self.$model.preferences.showInspector) {
                    InspectorView(
                        file: self.model.selectedFile,
                        session: self.model.session,
                        profile: self.model.activeProfile,
                        transferStats: self.model.transferStats,
                        lastConnection: self.model.lastConnectionDisplay
                    )
                    .inspectorColumnWidth(min: 240, ideal: 280, max: 420)
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
                },
                detect: { host, port, username in
                    await self.model.detectServer(host: host, port: port, username: username)
                }
            )
        }
        .alert(
            loc("detect.fixTitle"),
            isPresented: Binding(
                get: { self.model.pendingConnectionFix != nil },
                set: { if !$0 { self.model.pendingConnectionFix = nil } }
            )
        ) {
            Button(loc("delete.cancel"), role: .cancel) { self.model.pendingConnectionFix = nil }
            Button(loc("detect.fixApply")) { self.model.applyConnectionFix() }
        } message: {
            if let fix = self.model.pendingConnectionFix {
                Text(ServerProfileEditorView.summary(of: fix.detection))
            }
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

    private var activeFilterText: Binding<String> {
        Binding(
            get: { self.model.activePane == .local ? self.model.localFilterText : self.model.remoteFilterText },
            set: { text in
                if self.model.activePane == .local {
                    self.model.localFilterText = text
                } else {
                    self.model.remoteFilterText = text
                }
            }
        )
    }

    private var filterPrompt: String {
        loc("browser.filterPane", loc(self.model.activePane == .local ? "browser.local" : "browser.remote"))
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
                        .transition(.driftlineSlide(from: .bottom, reduceMotion: self.reduceMotion))
                }
            }
            .driftlineAnimation(value: self.model.preferences.showTransferQueue)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
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
                    filterText: self.$model.localFilterText,
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
                    filterText: self.$model.remoteFilterText,
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

    /// Bookmark and recent rows act on click and keep no selection; server rows select the server and connect.
    private static let newConnectionID = "action:new-connection"
    private static let bookmarkPrefix = "bookmark:"
    private static let recentPrefix = "recent:"

    var body: some View {
        // The system source list, as in Finder: title-case section headers, accent-tinted symbols,
        // the selection pill, keyboard navigation and the sidebar glass on macOS 26 and later.
        List(selection: self.selection) {
            // An action row on top: it opens Quick Connect and keeps no selection.
            Label(loc("sidebar.newConnection"), systemImage: "plus.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .tag(Self.newConnectionID)
                .help(loc("connection.newHint"))

            Section(loc("sidebar.favorites")) {
                let favorites = self.model.profiles.filter(\.isFavorite)
                if favorites.isEmpty {
                    self.emptyRow(loc("sidebar.markFavorites"))
                } else {
                    ForEach(favorites) { profile in
                        self.serverRow(profile, systemImage: "star")
                    }
                }
            }

            Section(loc("sidebar.savedServers")) {
                let servers = self.model.profiles.filter { !$0.isFavorite }
                if self.model.profiles.isEmpty {
                    self.emptyRow(loc("sidebar.noSavedServers"))
                } else {
                    // A favorite is listed once, in Favorites, as Finder lists each location once.
                    ForEach(servers) { profile in
                        self.serverRow(profile, systemImage: "server.rack")
                    }
                }
            }

            Section(loc("sidebar.bookmarks")) {
                if self.model.bookmarks.isEmpty {
                    self.emptyRow(loc("sidebar.noBookmarks"), detail: loc("sidebar.noBookmarksDetail"))
                } else {
                    ForEach(self.model.bookmarks) { bookmark in
                        Label(bookmark.name, systemImage: "bookmark")
                            .tag(Self.bookmarkPrefix + bookmark.id.uuidString)
                    }
                }
            }

            Section(loc("sidebar.recent")) {
                if self.model.recents.isEmpty {
                    self.emptyRow(loc("sidebar.noRecent"))
                } else {
                    ForEach(self.model.recents) { recent in
                        Label {
                            self.rowText(recent.displayName, subtitle: self.recentSubtitle(recent))
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .tag(Self.recentPrefix + recent.id.uuidString)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(loc("app.name"))
    }

    /// Selecting a row is the user's click: programmatic changes go through the model and never connect.
    private var selection: Binding<String?> {
        Binding(
            get: { self.model.selectedSidebarItem },
            set: { id in
                guard let id else { return }
                if id == Self.newConnectionID {
                    self.model.beginQuickConnect()
                } else if id.hasPrefix(Self.bookmarkPrefix) {
                    if let bookmark = self.model.bookmarks.first(where: { Self.bookmarkPrefix + $0.id.uuidString == id }) {
                        self.model.openBookmark(bookmark)
                    }
                } else if id.hasPrefix(Self.recentPrefix) {
                    if let recent = self.model.recents.first(where: { Self.recentPrefix + $0.id.uuidString == id }) {
                        self.model.openRecent(recent)
                    }
                } else {
                    self.model.selectedSidebarItem = id
                    self.model.connectToSelectedServer()
                }
            }
        )
    }

    private func serverRow(_ profile: ServerProfile, systemImage: String) -> some View {
        Label {
            HStack(spacing: 8) {
                self.rowText(profile.displayName, subtitle: self.profileSubtitle(profile))
                Spacer(minLength: 4)
                Circle()
                    .fill(self.statusColor(for: profile))
                    .frame(width: 6, height: 6)
                    .driftlineAnimation(value: self.statusColor(for: profile))
                    .accessibilityHidden(true)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .tag(self.sidebarID(for: profile))
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

    private func rowText(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// A hint row: not selectable, so it never takes the selection pill.
    private func emptyRow(_ text: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
            if let detail {
                Text(detail)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .selectionDisabled()
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
