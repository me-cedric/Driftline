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
    private let inspectorChromeTopExtension: CGFloat = 64

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
            ConnectionToolbar(model: self.model)
            TabStrip(model: self.model)
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
        .padding(.trailing, self.model.preferences.showInspector ? self.inspectorWidth + 1 : 0).toolbar {
            ToolbarItemGroup {
                Button { Task { await self.model.refreshLocal() } } label: {
                    Label(loc("browser.refresh"), systemImage: "arrow.clockwise")
                }
                .accessibilityHint(loc("browser.refreshHint"))
                Button { Task { await self.model.refreshRemote() } } label: {
                    Label(loc("browser.refreshRemote"), systemImage: "network")
                }
                .accessibilityHint(loc("browser.refreshRemoteHint"))
                Button { self.model.uploadSelectedItem() } label: {
                    Label(loc("browser.upload"), systemImage: "arrow.up.circle")
                }
                .disabled(self.model.selectedLocalFiles.isEmpty || self.model.session.state != .connected)
                .accessibilityHint(loc("browser.uploadHint"))
                Button { self.model.downloadSelectedItem() } label: {
                    Label(loc("browser.download"), systemImage: "arrow.down.circle")
                }
                .disabled(self.model.selectedRemoteFiles.isEmpty || self.model.session.state != .connected)
                .accessibilityHint(loc("browser.downloadHint"))
                Button { self.model.prepareSyncPreview() } label: {
                    Label(loc("browser.compare"), systemImage: "arrow.left.arrow.right")
                }
                .disabled(self.model.session.state != .connected)
                .accessibilityHint(loc("browser.compareHint"))
                Button { self.model.beginCreateFolder(source: self.model.selectedFile?.source ?? .local) } label: {
                    Label(loc("browser.newFolder"), systemImage: "folder.badge.plus")
                }
                Button { self.model.showViewOptions.toggle() } label: {
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
                Button { self.model.preferences.showInspector.toggle() } label: {
                    Label(loc("browser.inspector"), systemImage: "sidebar.right")
                }
            }
        }
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
                .fill(Color.primary.opacity(0.18))
                .frame(width: 1)
                .overlay {
                    Rectangle()
                        .fill(.clear)
                        .frame(width: 8)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
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
            InspectorView(file: self.model.selectedFile, session: self.model.session)
                .frame(width: self.inspectorWidth)
                .padding(.top, self.inspectorChromeTopExtension)
                .background(.bar)
        }
        .frame(maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    private var browserAndTransfers: some View {
        Group {
            if self.model.preferences.showTransferQueue {
                VSplitView {
                    GeometryReader { proxy in
                        self.fileBrowserSplit
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .frame(minHeight: 280)
                    GeometryReader { proxy in
                        self.transferQueue
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .frame(minHeight: 140, idealHeight: 170)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    self.fileBrowserSplit
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileBrowserSplit: some View {
        HSplitView {
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
            .frame(minWidth: 360, maxWidth: .infinity)
            .layoutPriority(1)
            FileBrowserPane(
                title: loc("browser.remote"),
                path: self.model.session.remotePath,
                items: self.model.remoteItems,
                source: .remote,
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
                loadChildren: { item, completion in self.model.loadChildren(of: item, completion: completion) }
            )
            .frame(minWidth: 360, maxWidth: .infinity)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transferQueue: some View {
        VStack(spacing: 0) {
            StatsDashboardView(stats: self.model.transferStats, lastConnection: self.model.lastConnectionDisplay)
            TransferPanel(
                jobs: self.model.transferJobs,
                onClearCompleted: { self.model.clearCompletedTransfers() },
                onClearFailed: { self.model.clearFailedTransfers() },
                onRetryFailed: { self.model.retryFailedTransfers() },
                onCancelActive: { self.model.cancelActiveTransfers() },
                onCancelTransfer: { self.model.cancelTransfer(id: $0) }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SidebarSection(title: loc("sidebar.driftline")) {
                    SidebarNavRow(
                        title: loc("sidebar.newConnection"),
                        systemImage: "plus.circle",
                        isSelected: false
                    ) {
                        self.model.beginQuickConnect()
                    }
                    SidebarNavRow(
                        title: loc("sidebar.saveServer"),
                        systemImage: "server.rack",
                        isSelected: false
                    ) {
                        self.model.beginCreatingProfile()
                    }
                }
                SidebarSection(title: loc("sidebar.savedServers")) {
                    if self.model.profiles.isEmpty {
                        SidebarEmptyRow(loc("sidebar.noSavedServers"))
                    } else {
                        ForEach(self.model.profiles) { profile in
                            SidebarNavRow(
                                title: profile.displayName,
                                subtitle: "\(profile.username)@\(profile.host):\(profile.port)",
                                systemImage: profile.isFavorite ? "star.fill" : "network",
                                isSelected: self.isSelected(profile)
                            ) {
                                self.model.selectedSidebarItem = self.sidebarID(for: profile)
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
                SidebarSection(title: loc("sidebar.favorites")) {
                    let favorites = self.model.profiles.filter(\.isFavorite)
                    if favorites.isEmpty {
                        SidebarEmptyRow(loc("sidebar.markFavorites"))
                    } else {
                        ForEach(favorites) { profile in
                            SidebarNavRow(
                                title: profile.displayName,
                                subtitle: "\(profile.username)@\(profile.host):\(profile.port)",
                                systemImage: "star.fill",
                                isSelected: self.isSelected(profile)
                            ) {
                                self.model.selectedSidebarItem = self.sidebarID(for: profile)
                                self.model.connectToSelectedServer()
                            }
                        }
                    }
                }
                SidebarSection(title: loc("sidebar.bookmarks")) {
                    if self.model.bookmarks.isEmpty {
                        SidebarEmptyRow(loc("sidebar.noBookmarks"))
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
                SidebarSection(title: loc("sidebar.recent")) {
                    if self.model.recents.isEmpty {
                        SidebarEmptyRow(loc("sidebar.noRecent"))
                    } else {
                        ForEach(self.model.recents) { recent in
                            SidebarNavRow(
                                title: recent.displayName,
                                systemImage: "clock",
                                isSelected: false
                            ) {
                                self.model.openRecent(recent)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .navigationTitle(loc("app.name"))
    }

    private func sidebarID(for profile: ServerProfile) -> String {
        profile.id.rawValue.uuidString
    }

    private func isSelected(_ profile: ServerProfile) -> Bool {
        self.model.selectedSidebarItem == self.sidebarID(for: profile)
    }
}

struct SidebarSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(self.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
                .padding(.horizontal, 10)
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
    var action: () -> Void

    @State private var isHovering = false

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            self.action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: self.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(self.iconColor)
                    .frame(width: 22, alignment: .center)
                VStack(alignment: .leading, spacing: 1) {
                    Text(self.title)
                        .font(.body.weight(self.isSelected ? .semibold : .regular))
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
            }
            .padding(.horizontal, 10)
            .padding(.vertical, self.subtitle == nil ? 8 : 7)
            .frame(maxWidth: .infinity, minHeight: self.subtitle == nil ? 36 : 46, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(self.backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.accentColor.opacity(self.isSelected ? 0.22 : 0), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { self.isHovering = $0 }
    }

    private var backgroundColor: Color {
        if self.isSelected {
            return Color.accentColor.opacity(0.16)
        }
        if self.isHovering {
            return Color.primary.opacity(0.07)
        }
        return .clear
    }

    private var iconColor: Color {
        self.isSelected ? .accentColor : Color.primary.opacity(0.74)
    }

    private var titleColor: Color {
        self.isSelected ? .accentColor : .primary
    }
}

struct SidebarEmptyRow: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(self.text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
    }
}

struct ConnectionToolbar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            ConnectionStatusPill(state: self.model.session.state)
            Text(self.model.activeProfile?.displayName ?? loc("connection.noServer"))
                .font(.headline)
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)
            Text(self.model.session.protocolKind?.rawValue.uppercased() ?? "SFTP")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.72))
            Spacer()
            Button {
                self.model.connectToSelectedServer()
            } label: {
                Label(self.model.isConnecting ? loc("connection.connecting") : loc("connection.connect"), systemImage: self.model.isConnecting ? "arrow.triangle.2.circlepath" : "link")
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.model.isConnecting)
            .help(loc("connection.connectHint"))
            .accessibilityLabel(self.model.isConnecting ? loc("connection.connecting") : loc("connection.connect"))
            .accessibilityHint(loc("connection.connectHint"))
            Button {
                self.model.beginQuickConnect()
            } label: {
                Label(loc("connection.new"), systemImage: "plus.circle")
            }
            .help(loc("connection.newHint"))
            .accessibilityLabel(loc("connection.new"))
            .accessibilityHint(loc("connection.newHint"))
            Button {
                self.model.beginEditingSelectedProfile()
            } label: {
                Label(loc("connection.edit"), systemImage: "pencil")
            }
            .disabled(self.model.selectedProfile == nil)
            .help(loc("connection.editHint"))
            .accessibilityLabel(loc("connection.edit"))
            Button {
                self.model.toggleSelectedFavorite()
            } label: {
                Label(loc("connection.favorite"), systemImage: self.model.selectedProfile?.isFavorite == true ? "star.fill" : "star")
            }
            .disabled(self.model.selectedProfile == nil)
            .help(self.model.selectedProfile?.isFavorite == true ? loc("connection.removeFavHint") : loc("connection.addFavHint"))
            .accessibilityLabel(self.model.selectedProfile?.isFavorite == true ? loc("connection.removeFavHint") : loc("connection.addFavHint"))
            Button {
                self.model.saveCurrentConnectionAsBookmark()
            } label: {
                Label(loc("connection.bookmark"), systemImage: "bookmark")
            }
            .disabled(self.model.activeProfile == nil || self.model.session.state != .connected)
            .help(loc("connection.bookmarkHint"))
            .accessibilityLabel(loc("connection.bookmark"))
            Button {
                self.model.openTerminalSession()
            } label: {
                Label(loc("connection.terminal"), systemImage: "terminal")
            }
            .disabled(self.model.activeProfile == nil)
            .help(loc("connection.terminalHint"))
            .accessibilityLabel(loc("connection.terminal"))
            .accessibilityHint(loc("connection.terminalHint"))
            Button {
                self.model.disconnect()
            } label: {
                Label(loc("connection.disconnect"), systemImage: "xmark.circle")
            }
            .disabled(self.model.session.state == .disconnected)
            .help(loc("connection.disconnectHint"))
            .accessibilityLabel(loc("connection.disconnect"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .labelStyle(.titleAndIcon)
    }
}

struct PulsingBlueDot: View {
    @State private var opacity = 1.0

    var body: some View {
        Circle()
            .fill(.blue)
            .frame(width: 7, height: 7)
            .opacity(self.opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    self.opacity = 0.35
                }
            }
    }
}

struct TabStrip: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(self.model.tabs) { tab in
                let isSelected = self.model.selectedTabID == tab.id
                HStack(spacing: 4) {
                    Button {
                        self.model.selectTab(tab.id)
                    } label: {
                        HStack(spacing: 5) {
                            switch tab.session.state {
                            case .connected:
                                Circle()
                                    .fill(.green)
                                    .frame(width: 7, height: 7)
                            case .connecting, .reconnecting:
                                PulsingBlueDot()
                            default:
                                EmptyView()
                            }
                            Text(tab.title)
                                .lineLimit(1)
                                .fontWeight(isSelected ? .semibold : .regular)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    if self.model.tabs.count > 1 {
                        Button {
                            self.model.requestCloseTab(tab.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .contentShape(Circle())
                        .accessibilityLabel(String(format: loc("tab.closeAction"), tab.title))
                        .padding(.trailing, 4)
                    }
                }
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7).fill(.selection)
                    } else {
                        RoundedRectangle(cornerRadius: 7).fill(.tertiary)
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7).stroke(.selection.opacity(0.5), lineWidth: 1)
                    }
                }
                .shadow(color: isSelected ? .black.opacity(0.10) : .clear, radius: 2, y: 1)
                .foregroundStyle(isSelected ? .primary : .secondary)
            }
            Button {
                self.model.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
