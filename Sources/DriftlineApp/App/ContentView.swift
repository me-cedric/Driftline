import DriftlineCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        HSplitView {
            if self.model.preferences.showSidebar {
                SidebarView(model: self.model)
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)
            }
            VStack(spacing: 0) {
                ConnectionToolbar(model: self.model)
                TabStrip(model: self.model)
                if let message = model.statusMessage {
                    StatusBanner(message: message) {
                        self.model.statusMessage = nil
                    }
                }
                HSplitView {
                    FileBrowserPane(
                        title: "Local",
                        path: self.model.session.localPath,
                        items: self.model.localItems,
                        selection: self.selectedFileBinding,
                        onOpen: { self.model.navigateLocal(to: $0) },
                        onParent: { self.model.navigateLocalParent() },
                        onRefresh: { Task { await self.model.refreshLocal() } },
                        onCreateFolder: { self.model.beginCreateFolder(source: .local) },
                        onRename: { self.model.beginRenameSelectedItem() },
                        onDelete: { self.model.requestDeleteSelectedItem() }
                    )
                    .frame(minWidth: 320, idealWidth: 380)
                    FileBrowserPane(
                        title: "Remote",
                        path: self.model.session.remotePath,
                        items: self.model.remoteItems,
                        selection: self.selectedFileBinding,
                        onOpen: { self.model.navigateRemote(to: $0) },
                        onParent: { self.model.navigateRemoteParent() },
                        onRefresh: { Task { await self.model.refreshRemote() } },
                        onCreateFolder: { self.model.beginCreateFolder(source: .remote) },
                        onRename: { self.model.beginRenameSelectedItem() },
                        onDelete: { self.model.requestDeleteSelectedItem() }
                    )
                    .frame(minWidth: 320, idealWidth: 380)
                }
                if self.model.preferences.showTransferQueue {
                    StatsDashboardView(stats: self.model.transferStats, lastConnection: self.model.lastConnectionDisplay)
                    TransferPanel(
                        jobs: self.model.transferJobs,
                        onClearCompleted: { self.model.clearCompletedTransfers() },
                        onClearFailed: { self.model.clearFailedTransfers() },
                        onRetryFailed: { self.model.retryFailedTransfers() },
                        onCancelActive: { self.model.cancelActiveTransfers() },
                        onCancelTransfer: { self.model.cancelTransfer(id: $0) }
                    )
                    .frame(height: 170)
                }
            }
            .frame(minWidth: 640)
            if self.model.preferences.showInspector {
                InspectorView(file: self.model.selectedFile, session: self.model.session)
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                    .background(.bar)
            }
        }
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
                    .disabled(self.model.selectedFile?.source != .local || self.model.session.state != .connected)
                    .accessibilityHint("Uploads the selected local item to the current remote folder.")
                    Button { self.model.downloadSelectedItem() } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .disabled(self.model.selectedFile?.source != .remote || self.model.session.state != .connected)
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

    private var selectedFileBinding: Binding<FileItem?> {
        Binding(
            get: { self.model.selectedFile },
            set: { selectedFile in
                self.model.selectedLocalFile = nil
                self.model.selectedRemoteFile = nil
                guard let selectedFile else { return }
                switch selectedFile.source {
                case .local:
                    self.model.selectedLocalFile = selectedFile
                    self.model.activePane = .local
                case .remote:
                    self.model.selectedRemoteFile = selectedFile
                    self.model.activePane = .remote
                }
            }
        )
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
        .frame(minWidth: 220)
        .navigationTitle("Driftline")
    }
}

struct ConnectionToolbar: View {
    @Bindable var model: AppModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            self.fullToolbar
            self.compactToolbar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var fullToolbar: some View {
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
            Button(self.model.isConnecting ? "Connecting..." : "Connect") { self.model.connectToSelectedServer() }
                .buttonStyle(.borderedProminent)
                .disabled(self.model.isConnecting)
                .accessibilityHint("Connects to the selected saved server.")
            Button("New") { self.model.beginQuickConnect() }
                .accessibilityHint("Opens a new connection form with credentials.")
            Button("Edit Server") { self.model.beginEditingSelectedProfile() }
                .disabled(self.model.selectedProfile == nil)
            Button("Favorite") { self.model.toggleSelectedFavorite() }
                .disabled(self.model.selectedProfile == nil)
            Button("Bookmark") { self.model.saveCurrentConnectionAsBookmark() }
                .disabled(self.model.activeProfile == nil || self.model.session.state != .connected)
            Button("Terminal") { self.model.openTerminalSession() }
                .disabled(self.model.activeProfile == nil)
                .accessibilityHint("Opens an SSH session in Terminal.")
            Button("Disconnect") { self.model.disconnect() }
                .disabled(self.model.session.state == .disconnected)
        }
    }

    private var compactToolbar: some View {
        HStack(spacing: 8) {
            ConnectionStatusPill(state: self.model.session.state)
            Text(self.model.activeProfile?.displayName ?? "No Server Selected")
                .font(.headline)
                .lineLimit(1)
                .frame(minWidth: 80, alignment: .leading)
            Text(self.model.session.protocolKind?.rawValue.uppercased() ?? "SFTP")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.72))
            Spacer(minLength: 8)
            Button { self.model.connectToSelectedServer() } label: {
                Image(systemName: self.model.isConnecting ? "arrow.triangle.2.circlepath" : "bolt.horizontal.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.model.isConnecting)
            .help(self.model.isConnecting ? "Connecting..." : "Connect")
            Button { self.model.beginQuickConnect() } label: {
                Image(systemName: "plus.circle")
            }
            .help("New Connection")
            Button { self.model.beginEditingSelectedProfile() } label: {
                Image(systemName: "pencil")
            }
            .disabled(self.model.selectedProfile == nil)
            .help("Edit Server")
            Button { self.model.toggleSelectedFavorite() } label: {
                Image(systemName: "star")
            }
            .disabled(self.model.selectedProfile == nil)
            .help("Favorite")
            Button { self.model.saveCurrentConnectionAsBookmark() } label: {
                Image(systemName: "bookmark")
            }
            .disabled(self.model.activeProfile == nil || self.model.session.state != .connected)
            .help("Bookmark")
            Button { self.model.openTerminalSession() } label: {
                Image(systemName: "terminal")
            }
            .disabled(self.model.activeProfile == nil)
            .help("Terminal")
            Button { self.model.disconnect() } label: {
                Image(systemName: "xmark.circle")
            }
            .disabled(self.model.session.state == .disconnected)
            .help("Disconnect")
        }
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
