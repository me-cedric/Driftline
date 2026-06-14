import DriftlineCore
import SwiftUI

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
            if let message = model.statusMessage {
                StatusBanner(message: message) {
                    self.model.statusMessage = nil
                }
            }
            self.browserAndTransfers
        }
        .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
        .padding(.trailing, self.model.preferences.showInspector ? self.inspectorWidth + 1 : 0)
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await self.model.refreshLocal() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .accessibilityHint("Refreshes the local file list.")
                Button { Task { await self.model.refreshRemote() } } label: {
                    Label("Refresh Remote", systemImage: "network")
                }
                .accessibilityHint("Refreshes the remote file list.")
                Button { self.model.uploadSelectedItem() } label: {
                    Label("Upload", systemImage: "arrow.up.circle")
                }
                .disabled(self.model.selectedLocalFiles.isEmpty || self.model.session.state != .connected)
                .accessibilityHint("Uploads the selected local item to the current remote folder.")
                Button { self.model.downloadSelectedItem() } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .disabled(self.model.selectedRemoteFiles.isEmpty || self.model.session.state != .connected)
                .accessibilityHint("Downloads the selected remote item to the current local folder.")
                Button { self.model.beginCreateFolder(source: self.model.selectedFile?.source ?? .local) } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                Button { self.model.showViewOptions.toggle() } label: {
                    Label("View Options", systemImage: "slider.horizontal.3")
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
                    Label("Inspector", systemImage: "sidebar.right")
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
        .alert("Delete Item?", isPresented: Binding(
            get: { self.model.pendingDeleteItem != nil },
            set: { if !$0 { self.model.pendingDeleteItem = nil } }
        )) {
            Button("Cancel", role: .cancel) { self.model.pendingDeleteItem = nil }
            Button("Delete", role: .destructive) { self.model.deletePendingItem() }
        } message: {
            Text(self.model.pendingDeleteItem?.name ?? "This item will be deleted.")
        }
        .sheet(item: self.$model.pendingTransferConflict) { conflict in
            TransferConflictView(
                conflict: conflict,
                renameText: self.$model.conflictRenameText,
                onSkip: { self.model.skipPendingConflict() },
                onOverwrite: { self.model.overwritePendingConflict() },
                onRename: { self.model.renameAndRunPendingConflict() }
            )
        }
        .sheet(isPresented: self.$model.showAbout) {
            AboutView()
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
                title: "Local",
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
                title: "Remote",
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
        List(selection: self.$model.selectedSidebarItem) {
            Section("Driftline") {
                Button {
                    self.model.beginQuickConnect()
                } label: {
                    Label("New Connection", systemImage: "plus.circle")
                }
                Button {
                    self.model.beginCreatingProfile()
                } label: {
                    Label("Save Server", systemImage: "server.rack")
                }
            }
            Section("Saved Servers") {
                if self.model.profiles.isEmpty {
                    SidebarEmptyRow("No saved servers")
                } else {
                    ForEach(self.model.profiles) { profile in
                        Button {
                            self.model.selectedSidebarItem = profile.id.rawValue.uuidString
                        } label: {
                            SidebarProfileRow(profile: profile)
                        }
                        .buttonStyle(.plain)
                        .tag(profile.id.rawValue.uuidString)
                        .contextMenu {
                            Button("Connect") {
                                self.model.selectedSidebarItem = profile.id.rawValue.uuidString
                                self.model.connectToSelectedServer()
                            }
                            Button("Edit") {
                                self.model.selectedSidebarItem = profile.id.rawValue.uuidString
                                self.model.beginEditingSelectedProfile()
                            }
                            Button("Duplicate") {
                                self.model.selectedSidebarItem = profile.id.rawValue.uuidString
                                self.model.duplicateSelectedProfile()
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                self.model.selectedSidebarItem = profile.id.rawValue.uuidString
                                self.model.deleteSelectedProfile()
                            }
                        }
                    }
                }
            }
            Section("Favorites") {
                let favorites = self.model.profiles.filter(\.isFavorite)
                if favorites.isEmpty {
                    SidebarEmptyRow("Mark servers as favorites")
                } else {
                    ForEach(favorites) { profile in
                        Button {
                            self.model.selectedSidebarItem = profile.id.rawValue.uuidString
                            self.model.connectToSelectedServer()
                        } label: {
                            Label(profile.displayName, systemImage: "star.fill")
                        }
                    }
                }
            }
            Section("Bookmarks") {
                if self.model.bookmarks.isEmpty {
                    SidebarEmptyRow("No bookmarks saved")
                } else {
                    ForEach(self.model.bookmarks) { bookmark in
                        Button {
                            self.model.openBookmark(bookmark)
                        } label: {
                            Label(bookmark.name, systemImage: "bookmark")
                        }
                    }
                }
            }
            Section("Recent") {
                if self.model.recents.isEmpty {
                    SidebarEmptyRow("No recent connections")
                } else {
                    ForEach(self.model.recents) { recent in
                        Button {
                            self.model.openRecent(recent)
                        } label: {
                            Label(recent.displayName, systemImage: "clock")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Driftline")
    }
}

struct ConnectionToolbar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            ConnectionStatusPill(state: self.model.session.state)
            Text(self.model.activeProfile?.displayName ?? "No Server Selected")
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
                Label(self.model.isConnecting ? "Connecting..." : "Connect", systemImage: self.model.isConnecting ? "arrow.triangle.2.circlepath" : "link")
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.model.isConnecting)
            .help("Connect to the selected saved server.")
            .accessibilityLabel(self.model.isConnecting ? "Connecting" : "Connect")
            .accessibilityHint("Connects to the selected saved server.")
            Button {
                self.model.beginQuickConnect()
            } label: {
                Label("New", systemImage: "plus.circle")
            }
            .help("Create a new connection.")
            .accessibilityLabel("New connection")
            .accessibilityHint("Opens a new connection form with credentials.")
            Button {
                self.model.beginEditingSelectedProfile()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .disabled(self.model.selectedProfile == nil)
            .help("Edit the selected server.")
            .accessibilityLabel("Edit selected server")
            Button {
                self.model.toggleSelectedFavorite()
            } label: {
                Label("Favorite", systemImage: self.model.selectedProfile?.isFavorite == true ? "star.fill" : "star")
            }
            .disabled(self.model.selectedProfile == nil)
            .help(self.model.selectedProfile?.isFavorite == true ? "Remove the selected server from favorites." : "Add the selected server to favorites.")
            .accessibilityLabel(self.model.selectedProfile?.isFavorite == true ? "Remove favorite" : "Add favorite")
            Button {
                self.model.saveCurrentConnectionAsBookmark()
            } label: {
                Label("Bookmark", systemImage: "bookmark")
            }
            .disabled(self.model.activeProfile == nil || self.model.session.state != .connected)
            .help("Save the current local and remote paths as a bookmark.")
            .accessibilityLabel("Bookmark current connection")
            Button {
                self.model.openTerminalSession()
            } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .disabled(self.model.activeProfile == nil)
            .help("Open an SSH session in Terminal.")
            .accessibilityLabel("Open Terminal session")
            .accessibilityHint("Opens an SSH session in Terminal.")
            Button {
                self.model.disconnect()
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
            .disabled(self.model.session.state == .disconnected)
            .help("Disconnect from the current server.")
            .accessibilityLabel("Disconnect")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .labelStyle(.titleAndIcon)
    }
}

struct SidebarProfileRow: View {
    var profile: ServerProfile

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(self.profile.displayName)
                    .lineLimit(1)
                Text("\(self.profile.username)@\(self.profile.host):\(self.profile.port)")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.62))
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: self.profile.isFavorite ? "star.fill" : "network")
        }
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
            .foregroundStyle(.primary.opacity(0.55))
            .padding(.vertical, 4)
    }
}

struct StatusBanner: View {
    var message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
            Text(self.message)
                .lineLimit(2)
            Spacer()
            Button(action: self.onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

struct TabStrip: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(self.model.tabs) { tab in
                Button {
                    self.model.selectTab(tab.id)
                } label: {
                    Text(tab.title)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderless)
                .background(self.model.selectedTabID == tab.id ? .regularMaterial : .thinMaterial, in: RoundedRectangle(cornerRadius: 7))
            }
            Button { self.model.newTab() } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }
}
