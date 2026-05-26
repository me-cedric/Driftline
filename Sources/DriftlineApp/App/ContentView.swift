import DriftlineCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            if model.preferences.showSidebar {
                SidebarView(model: model)
            } else {
                EmptyView()
            }
        } detail: {
            VStack(spacing: 0) {
                ConnectionToolbar(model: model)
                TabStrip(model: model)
                if let message = model.statusMessage {
                    StatusBanner(message: message) {
                        model.statusMessage = nil
                    }
                }
                HSplitView {
                    FileBrowserPane(
                        title: "Local",
                        path: model.session.localPath,
                        items: model.localItems,
                        selection: $model.selectedFile,
                        onOpen: { model.navigateLocal(to: $0) },
                        onParent: { model.navigateLocalParent() },
                        onRefresh: { Task { await model.refreshLocal() } },
                        onCreateFolder: { model.beginCreateFolder(source: .local) },
                        onRename: { model.beginRenameSelectedItem() },
                        onDelete: { model.requestDeleteSelectedItem() }
                    )
                        .frame(minWidth: 360)
                    FileBrowserPane(
                        title: "Remote",
                        path: model.session.remotePath,
                        items: model.remoteItems,
                        selection: $model.selectedFile,
                        onOpen: { model.navigateRemote(to: $0) },
                        onParent: { model.navigateRemoteParent() },
                        onRefresh: { Task { await model.refreshRemote() } },
                        onCreateFolder: { model.beginCreateFolder(source: .remote) },
                        onRename: { model.beginRenameSelectedItem() },
                        onDelete: { model.requestDeleteSelectedItem() }
                    )
                        .frame(minWidth: 360)
                }
                if model.preferences.showTransferQueue {
                    StatsDashboardView(stats: model.transferStats, lastConnection: model.lastConnectionDisplay)
                    TransferPanel(
                        jobs: model.transferJobs,
                        onClearCompleted: { model.clearCompletedTransfers() },
                        onClearFailed: { model.clearFailedTransfers() },
                        onRetryFailed: { model.retryFailedTransfers() },
                        onCancelActive: { model.cancelActiveTransfers() },
                        onCancelTransfer: { model.cancelTransfer(id: $0) }
                    )
                        .frame(height: 170)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button { Task { await model.refreshLocal() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .accessibilityHint("Refreshes the local file list.")
                    Button { Task { await model.refreshRemote() } } label: {
                        Label("Refresh Remote", systemImage: "network")
                    }
                    .accessibilityHint("Refreshes the remote file list.")
                    Button { model.uploadSelectedItem() } label: {
                        Label("Upload", systemImage: "arrow.up.circle")
                    }
                    .disabled(model.selectedFile?.source != .local || model.session.state != .connected)
                    .accessibilityHint("Uploads the selected local item to the current remote folder.")
                    Button { model.downloadSelectedItem() } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .disabled(model.selectedFile?.source != .remote || model.session.state != .connected)
                    .accessibilityHint("Downloads the selected remote item to the current local folder.")
                    Button { model.beginCreateFolder(source: model.selectedFile?.source ?? .local) } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    Button { model.showViewOptions.toggle() } label: {
                        Label("View Options", systemImage: "slider.horizontal.3")
                    }
                    .popover(isPresented: $model.showViewOptions) {
                        ViewOptionsView(preferences: $model.preferences) {
                            model.savePreferences()
                            Task {
                                await model.refreshLocal()
                                await model.refreshRemote()
                            }
                        }
                    }
                    Button { model.preferences.showInspector.toggle() } label: {
                        Label("Inspector", systemImage: "sidebar.right")
                    }
                }
            }
            .inspector(isPresented: $model.preferences.showInspector) {
                InspectorView(file: model.selectedFile, session: model.session)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
            }
            .sheet(item: $model.profileDraft) { draft in
                ServerProfileEditorView(
                    draft: Binding(
                        get: { model.profileDraft ?? draft },
                        set: { model.profileDraft = $0 }
                    ),
                    savesAndConnects: model.connectAfterSavingDraft,
                    errorMessage: model.profileEditorError,
                    onCancel: {
                        model.profileDraft = nil
                        model.profileEditorError = nil
                        model.connectAfterSavingDraft = false
                    },
                    onSave: {
                        model.saveProfileDraft()
                    }
                )
            }
            .sheet(item: $model.pendingHostTrust) { trust in
                HostTrustPromptView(
                    trust: trust,
                    onCancel: { model.pendingHostTrust = nil },
                    onTrust: { model.trustPendingHostAndReconnect() }
                )
            }
            .sheet(item: $model.fileOperationPrompt) { prompt in
                FileOperationPromptView(
                    title: prompt.title,
                    text: $model.fileOperationText,
                    onCancel: {
                        model.fileOperationPrompt = nil
                        model.fileOperationText = ""
                    },
                    onCommit: {
                        model.commitFileOperationPrompt()
                    }
                )
            }
            .alert("Delete Item?", isPresented: Binding(
                get: { model.pendingDeleteItem != nil },
                set: { if !$0 { model.pendingDeleteItem = nil } }
            )) {
                Button("Cancel", role: .cancel) { model.pendingDeleteItem = nil }
                Button("Delete", role: .destructive) { model.deletePendingItem() }
            } message: {
                Text(model.pendingDeleteItem?.name ?? "This item will be deleted.")
            }
            .sheet(item: $model.pendingTransferConflict) { conflict in
                TransferConflictView(
                    conflict: conflict,
                    renameText: $model.conflictRenameText,
                    onSkip: { model.skipPendingConflict() },
                    onOverwrite: { model.overwritePendingConflict() },
                    onRename: { model.renameAndRunPendingConflict() }
                )
            }
            .sheet(isPresented: $model.showAbout) {
                AboutView()
            }
        }
    }
}

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selectedSidebarItem) {
            Section("Driftline") {
                Button {
                    model.beginQuickConnect()
                } label: {
                    Label("New Connection", systemImage: "plus.circle")
                }
                Button {
                    model.beginCreatingProfile()
                } label: {
                    Label("Save Server", systemImage: "server.rack")
                }
            }
            Section("Saved Servers") {
                if model.profiles.isEmpty {
                    SidebarEmptyRow("No saved servers")
                } else {
                    ForEach(model.profiles) { profile in
                        Button {
                            model.selectedSidebarItem = profile.id.rawValue.uuidString
                        } label: {
                            SidebarProfileRow(profile: profile)
                        }
                        .buttonStyle(.plain)
                        .tag(profile.id.rawValue.uuidString)
                        .contextMenu {
                            Button("Connect") {
                                model.selectedSidebarItem = profile.id.rawValue.uuidString
                                model.connectToSelectedServer()
                            }
                            Button("Edit") {
                                model.selectedSidebarItem = profile.id.rawValue.uuidString
                                model.beginEditingSelectedProfile()
                            }
                            Button("Duplicate") {
                                model.selectedSidebarItem = profile.id.rawValue.uuidString
                                model.duplicateSelectedProfile()
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                model.selectedSidebarItem = profile.id.rawValue.uuidString
                                model.deleteSelectedProfile()
                            }
                        }
                    }
                }
            }
            Section("Favorites") {
                let favorites = model.profiles.filter(\.isFavorite)
                if favorites.isEmpty {
                    SidebarEmptyRow("Mark servers as favorites")
                } else {
                    ForEach(favorites) { profile in
                        Button {
                            model.selectedSidebarItem = profile.id.rawValue.uuidString
                            model.connectToSelectedServer()
                        } label: {
                            Label(profile.displayName, systemImage: "star.fill")
                        }
                    }
                }
            }
            Section("Bookmarks") {
                if model.bookmarks.isEmpty {
                    SidebarEmptyRow("No bookmarks saved")
                } else {
                    ForEach(model.bookmarks) { bookmark in
                        Button {
                            model.openBookmark(bookmark)
                        } label: {
                            Label(bookmark.name, systemImage: "bookmark")
                        }
                    }
                }
            }
            Section("Recent") {
                if model.recents.isEmpty {
                    SidebarEmptyRow("No recent connections")
                } else {
                    ForEach(model.recents) { recent in
                        Button {
                            model.openRecent(recent)
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
            ConnectionStatusPill(state: model.session.state)
            Text(model.activeProfile?.displayName ?? "No Server Selected")
                .font(.headline)
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)
            Text(model.session.protocolKind?.rawValue.uppercased() ?? "SFTP")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.72))
            Spacer()
            Button(model.isConnecting ? "Connecting..." : "Connect") { model.connectToSelectedServer() }
                .buttonStyle(.borderedProminent)
                .disabled(model.isConnecting)
                .accessibilityHint("Connects to the selected saved server.")
            Button("New") { model.beginQuickConnect() }
                .accessibilityHint("Opens a new connection form with credentials.")
            Button("Edit Server") { model.beginEditingSelectedProfile() }
                .disabled(model.selectedProfile == nil)
            Button("Favorite") { model.toggleSelectedFavorite() }
                .disabled(model.selectedProfile == nil)
            Button("Bookmark") { model.saveCurrentConnectionAsBookmark() }
                .disabled(model.activeProfile == nil || model.session.state != .connected)
            Button("Terminal") { model.openTerminalSession() }
                .disabled(model.activeProfile == nil)
                .accessibilityHint("Opens an SSH session in Terminal.")
            Button("Disconnect") { model.disconnect() }
                .disabled(model.session.state == .disconnected)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct SidebarProfileRow: View {
    var profile: ServerProfile

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .lineLimit(1)
                Text("\(profile.username)@\(profile.host):\(profile.port)")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.62))
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: profile.isFavorite ? "star.fill" : "network")
        }
    }
}

struct SidebarEmptyRow: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
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
            Text(message)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
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
            ForEach(model.tabs) { tab in
                Button {
                    model.selectTab(tab.id)
                } label: {
                    Text(tab.title)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderless)
                .background(model.selectedTabID == tab.id ? .regularMaterial : .thinMaterial, in: RoundedRectangle(cornerRadius: 7))
            }
            Button { model.newTab() } label: {
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
