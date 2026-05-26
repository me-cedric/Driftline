import AppKit
import DriftlineCore
import SwiftUI

@main
struct DriftlineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Driftline", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 1180, minHeight: 720)
        }
        .commands {
            DriftlineCommands(model: model)
        }

        Settings {
            SettingsView(preferences: $model.preferences)
                .onChange(of: model.preferences) { _, _ in
                    model.savePreferences()
                }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
@Observable
final class AppModel: @unchecked Sendable {
    var selectedSidebarItem: SidebarItem.ID? = SidebarItem.quickConnect.id
    var tabs: [WorkspaceTab] = [WorkspaceTab()]
    var selectedTabID: WorkspaceTab.ID?
    var preferences = ViewPreferences()
    var localItems: [FileItem] = []
    var remoteItems: [FileItem] = []
    var selectedFile: FileItem?
    var profileDraft: ServerProfileDraft?
    var profileEditorError: String?
    var isConnecting = false
    var pendingHostTrust: PendingHostTrust?
    var fileOperationPrompt: FileOperationPrompt?
    var fileOperationText = ""
    var pendingDeleteItem: FileItem?
    var pendingTransferConflict: TransferConflict?
    var conflictRenameText = ""
    var bookmarks: [ServerBookmark] = []
    var recents: [RecentServer] = []
    var connectAfterSavingDraft = false
    var showViewOptions = false
    var showAbout = false
    var statusMessage: String?
    var transferJobs: [TransferJob] = []
    var transferProfiles: [TransferJobID: ServerProfile] = [:]
    var profiles: [ServerProfile] = []
    var session = ConnectionSession(state: .disconnected, protocolKind: .sftp)
    var transferStats: TransferStats {
        TransferStatsCalculator.calculate(from: transferJobs)
    }

    var lastConnectionDisplay: String {
        guard let connectedAt = session.connectedAt else { return "None" }
        return connectedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private let localFileSystem: LocalFileSystemClient = FoundationLocalFileSystemClient()
    private let profileRepository: ServerProfileRepository
    private let preferencesRepository: ViewPreferencesRepository
    private let transferHistoryRepository: TransferHistoryRepository
    private let bookmarkRepository: ServerBookmarkRepository
    private let recentRepository: RecentServerRepository
    private let remoteFileSystem: RemoteFileSystemClient
    private let nativeRemoteFileSystem: RemoteFileSystemClient
    private let transferClient: TransferClient
    private let nativeTransferClient: TransferClient
    private let hostTrustStore: HostTrustStore
    private let knownHostsFile: ManagedKnownHostsFile
    private let terminalLauncher: TerminalLaunching
    private let credentialStore: CredentialStore

    init(
        profileRepository: ServerProfileRepository = JSONServerProfileRepository(),
        preferencesRepository: ViewPreferencesRepository = JSONViewPreferencesRepository(),
        transferHistoryRepository: TransferHistoryRepository = JSONTransferHistoryRepository(),
        bookmarkRepository: ServerBookmarkRepository = JSONServerBookmarkRepository(),
        recentRepository: RecentServerRepository = JSONRecentServerRepository(),
        remoteFileSystem: RemoteFileSystemClient = SystemSFTPClient.secureDefault(),
        nativeRemoteFileSystem: RemoteFileSystemClient? = nil,
        transferClient: TransferClient = SystemRsyncTransferClient(),
        nativeTransferClient: TransferClient? = nil,
        hostTrustStore: HostTrustStore = JSONHostTrustStore(),
        knownHostsFile: ManagedKnownHostsFile = ManagedKnownHostsFile(),
        terminalLauncher: TerminalLaunching = SystemTerminalLauncher(),
        credentialStore: CredentialStore = KeychainCredentialStore()
    ) {
        self.profileRepository = profileRepository
        self.preferencesRepository = preferencesRepository
        self.transferHistoryRepository = transferHistoryRepository
        self.bookmarkRepository = bookmarkRepository
        self.recentRepository = recentRepository
        self.remoteFileSystem = remoteFileSystem
        self.nativeRemoteFileSystem = nativeRemoteFileSystem ?? NativeSFTPClient(credentialStore: credentialStore, hostTrustStore: hostTrustStore)
        self.transferClient = transferClient
        self.nativeTransferClient = nativeTransferClient ?? NativeSFTPTransferClient(credentialStore: credentialStore, hostTrustStore: hostTrustStore)
        self.hostTrustStore = hostTrustStore
        self.knownHostsFile = knownHostsFile
        self.terminalLauncher = terminalLauncher
        self.credentialStore = credentialStore
        selectedTabID = tabs.first?.id
        Task { await loadInitialState() }
    }

    func loadInitialState() async {
        do {
            preferences = try await preferencesRepository.load()
            profiles = try await profileRepository.list()
            bookmarks = try await bookmarkRepository.list()
            recents = try await recentRepository.list(limit: 10)
            transferJobs = try await transferHistoryRepository.list(limit: 100)
            consumeLaunchRequest()
            await refreshLocal()
        } catch {
            session.lastErrorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
            await refreshLocal()
        }
    }

    private func consumeLaunchRequest() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--driftline-open"), args.indices.contains(index + 1) {
            if args.contains("--driftline-new-tab") {
                newTab()
            }
            session.localPath = args[index + 1]
            return
        }
        if let request = try? CLIRequestStore.consume() {
            if request.openInNewTab {
                newTab()
            }
            session.localPath = request.localPath
        }
    }

    func refreshLocal() async {
        do {
            localItems = try await localFileSystem.listDirectory(at: session.localPath, preferences: preferences.fileList)
            saveActiveTabSnapshot()
        } catch {
            localItems = []
            session.lastErrorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    func navigateLocal(to item: FileItem) {
        guard item.source == .local else { return }
        if item.kind == .folder {
            session.localPath = item.path
            Task { await refreshLocal() }
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
        }
    }

    func navigateRemote(to item: FileItem) {
        guard item.source == .remote, item.kind == .folder else { return }
        session.remotePath = item.path
        Task { await refreshRemote() }
    }

    func navigateLocalParent() {
        let parent = URL(fileURLWithPath: session.localPath).deletingLastPathComponent().path
        guard parent != session.localPath else { return }
        session.localPath = parent
        Task { await refreshLocal() }
    }

    func navigateRemoteParent() {
        guard session.remotePath != "/" else { return }
        let parent = URL(fileURLWithPath: session.remotePath).deletingLastPathComponent().path
        session.remotePath = parent.isEmpty ? "/" : parent
        Task { await refreshRemote() }
    }

    func beginQuickConnect() {
        connectAfterSavingDraft = true
        beginCreatingProfile()
    }

    func connectToSelectedServer() {
        Task { await connectSelectedServer() }
    }

    func connectSelectedServer() async {
        guard let profile = selectedProfile else {
            statusMessage = "Select a saved server or create a new connection."
            beginQuickConnect()
            return
        }
        await connect(profile)
    }

    private func connect(_ profile: ServerProfile) async {
        isConnecting = true
        session = ConnectionSession(serverID: profile.id, state: .connecting, protocolKind: profile.protocolKind, localPath: profile.localDefaultPath, remotePath: profile.remoteDefaultPath)
        do {
            let client = remoteClientForCurrentPreference()
            session = try await client.connect(to: profile)
            remoteItems = try await client.listDirectory(at: session.remotePath, profile: profile, session: session, preferences: preferences.fileList)
            try await recentRepository.record(RecentServer(
                profileID: profile.id,
                displayName: profile.displayName,
                host: profile.host,
                protocolKind: profile.protocolKind,
                localPath: session.localPath,
                remotePath: session.remotePath
            ), limit: 10)
            recents = try await recentRepository.list(limit: 10)
            saveActiveTabSnapshot()
            isConnecting = false
        } catch {
            remoteItems = []
            if case RemoteClientError.hostNotTrusted(let host, let port, let algorithm, let fingerprint, let knownHostsLine) = error {
                pendingHostTrust = PendingHostTrust(host: host, port: port, algorithm: algorithm, fingerprint: fingerprint, knownHostsLine: knownHostsLine)
            }
            session.state = .failed(message: error.localizedDescription)
            session.lastErrorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
            isConnecting = false
        }
    }

    func trustPendingHostAndReconnect() {
        guard let pendingHostTrust else { return }
        Task {
            do {
                let record = HostTrustRecord(
                    host: pendingHostTrust.host,
                    port: pendingHostTrust.port,
                    algorithm: pendingHostTrust.algorithm,
                    fingerprint: pendingHostTrust.fingerprint,
                    knownHostsLine: pendingHostTrust.knownHostsLine
                )
                try await hostTrustStore.trust(record)
                try await knownHostsFile.trust(record)
                self.pendingHostTrust = nil
                await connectSelectedServer()
            } catch {
                session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func refreshRemote() async {
        guard let profile = activeProfile, session.state == .connected else { return }
        do {
            remoteItems = try await remoteClientForCurrentPreference().listDirectory(at: session.remotePath, profile: profile, session: session, preferences: preferences.fileList)
            saveActiveTabSnapshot()
        } catch {
            session.state = .failed(message: error.localizedDescription)
            session.lastErrorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    func disconnect() {
        session.state = .disconnected
        remoteItems = []
    }

    func savePreferences() {
        let current = preferences
        Task {
            try? await preferencesRepository.save(current)
        }
    }

    var selectedProfile: ServerProfile? {
        guard let selectedSidebarItem else { return nil }
        return profiles.first { $0.id.rawValue.uuidString == selectedSidebarItem }
    }

    func toggleSelectedFavorite() {
        guard var selectedProfile else { return }
        selectedProfile.isFavorite.toggle()
        Task {
            do {
                try await profileRepository.save(selectedProfile)
                profiles = try await profileRepository.list()
                statusMessage = selectedProfile.isFavorite ? "Added to favorites." : "Removed from favorites."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func saveCurrentConnectionAsBookmark() {
        guard let profile = activeProfile else { return }
        let bookmark = ServerBookmark(
            profileID: profile.id,
            name: "\(profile.displayName): \(session.remotePath)",
            localPath: session.localPath,
            remotePath: session.remotePath
        )
        Task {
            do {
                try await bookmarkRepository.save(bookmark)
                bookmarks = try await bookmarkRepository.list()
                statusMessage = "Saved bookmark."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func openBookmark(_ bookmark: ServerBookmark) {
        guard profiles.contains(where: { $0.id == bookmark.profileID }) else { return }
        selectedSidebarItem = bookmark.profileID.rawValue.uuidString
        session.localPath = bookmark.localPath
        session.remotePath = bookmark.remotePath
        Task {
            await refreshLocal()
            await connectSelectedServer()
        }
    }

    func openRecent(_ recent: RecentServer) {
        selectedSidebarItem = recent.profileID.rawValue.uuidString
        session.localPath = recent.localPath
        session.remotePath = recent.remotePath
        Task {
            await refreshLocal()
            await connectSelectedServer()
        }
    }

    func reconnectLastServer() {
        if let recent = recents.first {
            openRecent(recent)
        } else {
            beginQuickConnect()
        }
    }

    func beginCreatingProfile() {
        connectAfterSavingDraft = false
        profileEditorError = nil
        profileDraft = ServerProfileDraft()
    }

    func beginEditingSelectedProfile() {
        guard let selectedProfile else { return }
        profileEditorError = nil
        profileDraft = ServerProfileDraft(profile: selectedProfile)
    }

    func saveProfileDraft() {
        guard let draft = profileDraft else { return }
        do {
            let profile = draft.makeProfile()
            try ServerProfileValidator.validate(profile)
            Task {
                do {
                    try await saveCredentialSecrets(from: draft, profile: profile)
                    try await profileRepository.save(profile)
                    profiles = try await profileRepository.list()
                    selectedSidebarItem = profile.id.rawValue.uuidString
                    profileDraft = nil
                    profileEditorError = nil
                    if connectAfterSavingDraft {
                        connectAfterSavingDraft = false
                        await connect(profile)
                    }
                } catch {
                    profileEditorError = error.localizedDescription
                }
            }
        } catch {
            profileEditorError = error.localizedDescription
        }
    }

    private func saveCredentialSecrets(from draft: ServerProfileDraft, profile: ServerProfile) async throws {
        switch profile.authenticationMethod {
        case .password(let reference):
            if !draft.password.isEmpty {
                try await credentialStore.saveString(draft.password, reference: reference)
            }
        case .privateKey(_, let passphraseReference):
            if let passphraseReference, !draft.passphrase.isEmpty {
                try await credentialStore.saveString(draft.passphrase, reference: passphraseReference)
            }
        case .agent, .none:
            break
        }
    }

    func duplicateSelectedProfile() {
        guard let selectedProfile else { return }
        let copy = selectedProfile.duplicated()
        Task {
            do {
                try await profileRepository.save(copy)
                profiles = try await profileRepository.list()
                selectedSidebarItem = copy.id.rawValue.uuidString
            } catch {
                session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func deleteSelectedProfile() {
        guard let selectedProfile else { return }
        Task {
            do {
                try await profileRepository.delete(id: selectedProfile.id)
                profiles = try await profileRepository.list()
                    selectedSidebarItem = nil
                if session.serverID == selectedProfile.id {
                    disconnect()
                }
            } catch {
                session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func beginCreateFolder(source: FileSource) {
        fileOperationText = "New Folder"
        fileOperationPrompt = FileOperationPrompt(kind: .createFolder, source: source)
    }

    func beginRenameSelectedItem() {
        guard let selectedFile else { return }
        fileOperationText = selectedFile.name
        fileOperationPrompt = FileOperationPrompt(kind: .rename(selectedFile), source: selectedFile.source)
    }

    func requestDeleteSelectedItem() {
        guard let selectedFile else { return }
        if preferences.confirmBeforeDelete {
            pendingDeleteItem = selectedFile
        } else {
            deleteItem(selectedFile)
        }
    }

    func commitFileOperationPrompt() {
        guard let prompt = fileOperationPrompt else { return }
        let value = fileOperationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        switch prompt.kind {
        case .createFolder:
            createFolder(named: value, source: prompt.source)
        case .rename(let item):
            renameItem(item, to: value)
        }
        fileOperationPrompt = nil
        fileOperationText = ""
    }

    func deletePendingItem() {
        guard let pendingDeleteItem else { return }
        deleteItem(pendingDeleteItem)
        self.pendingDeleteItem = nil
    }

    private func createFolder(named name: String, source: FileSource) {
        Task {
            do {
                switch source {
                case .local:
                    try await localFileSystem.createFolder(named: name, in: session.localPath)
                    await refreshLocal()
                case .remote:
                    guard let profile = activeProfile else { return }
                    try await remoteClientForCurrentPreference().createFolder(named: name, in: session.remotePath, profile: profile, session: session)
                    await refreshRemote()
                }
            } catch {
                session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func renameItem(_ item: FileItem, to newName: String) {
        Task {
            do {
                switch item.source {
                case .local:
                    try await localFileSystem.renameItem(at: item.path, to: newName)
                    await refreshLocal()
                case .remote:
                    guard let profile = activeProfile else { return }
                    try await remoteClientForCurrentPreference().renameItem(at: item.path, to: newName, profile: profile, session: session)
                    await refreshRemote()
                }
            } catch {
                session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteItem(_ item: FileItem) {
        Task {
            do {
                switch item.source {
                case .local:
                    try await localFileSystem.deleteItem(at: item.path)
                    selectedFile = nil
                    await refreshLocal()
                case .remote:
                    guard let profile = activeProfile else { return }
                    try await remoteClientForCurrentPreference().deleteItem(at: item.path, profile: profile, session: session)
                    selectedFile = nil
                    await refreshRemote()
                }
            } catch {
                session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func uploadSelectedItem() {
        guard let profile = activeProfile,
              let selectedFile,
              selectedFile.source == .local,
              session.state == .connected
        else { return }
        let destination = remotePathAppending(session.remotePath, selectedFile.name)
        let job = TransferJob(
            direction: .upload,
            sourcePath: selectedFile.path,
            destinationPath: destination,
            byteCount: selectedFile.size,
            serverName: profile.displayName,
            protocolKind: profile.protocolKind
        )
        if preferences.confirmBeforeOverwrite, remoteItems.contains(where: { $0.path == destination }) {
            pendingTransferConflict = TransferConflict(job: job, profile: profile, existingPath: destination)
            conflictRenameText = suggestedConflictName(for: selectedFile.name)
            return
        }
        enqueueTransfer(job, profile: profile)
    }

    func openTerminalSession() {
        guard let profile = activeProfile else { return }
        Task {
            do {
                let command = try TerminalCommandFactory.sshCommand(for: profile)
                try await terminalLauncher.launch(command)
            } catch {
                session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func downloadSelectedItem() {
        guard let profile = activeProfile,
              let selectedFile,
              selectedFile.source == .remote,
              session.state == .connected
        else { return }
        let destination = URL(fileURLWithPath: session.localPath).appendingPathComponent(selectedFile.name).path
        let job = TransferJob(
            direction: .download,
            sourcePath: selectedFile.path,
            destinationPath: destination,
            byteCount: selectedFile.size,
            serverName: profile.displayName,
            protocolKind: profile.protocolKind
        )
        if preferences.confirmBeforeOverwrite, FileManager.default.fileExists(atPath: destination) {
            pendingTransferConflict = TransferConflict(job: job, profile: profile, existingPath: destination)
            conflictRenameText = suggestedConflictName(for: selectedFile.name)
            return
        }
        enqueueTransfer(job, profile: profile)
    }

    private func enqueueTransfer(_ job: TransferJob, profile: ServerProfile) {
        var queued = job
        queued.status = .queued
        transferProfiles[queued.id] = profile
        replaceTransferJob(queued)
        processTransferQueue()
    }

    private func processTransferQueue() {
        let runningCount = transferJobs.filter(\.isRunning).count
        let capacity = max(preferences.transferConcurrency - runningCount, 0)
        guard capacity > 0 else { return }

        let queuedJobs = transferJobs.filter(\.isQueued).prefix(capacity)
        for job in queuedJobs {
            guard let profile = transferProfiles[job.id] else { continue }
            var starting = job
            starting.status = .running(progress: 0, bytesPerSecond: nil)
            starting.startedAt = Date()
            replaceTransferJob(starting)
            Task {
                await runTransfer(starting, profile: profile)
            }
        }
    }

    private func runTransfer(_ job: TransferJob, profile: ServerProfile) async {
        do {
            let updateModel = self
            let client = transferClientForCurrentPreference()
            try await client.enqueue(job, profile: profile) { [updateModel] updated in
                await MainActor.run {
                    updateModel.replaceTransferJob(updated)
                }
            }
            transferJobs = await client.jobs().reversed()
            if let completed = transferJobs.first(where: { $0.id == job.id }) {
                try? await transferHistoryRepository.append(completed)
            }
            transferProfiles[job.id] = nil
            await refreshLocal()
            await refreshRemote()
        } catch {
            var failed = job
            failed.status = .failed(message: error.localizedDescription)
            failed.finishedAt = Date()
            transferJobs.removeAll { $0.id == job.id }
            transferJobs.insert(failed, at: 0)
            transferProfiles[job.id] = nil
            try? await transferHistoryRepository.append(failed)
        }
        processTransferQueue()
    }

    func skipPendingConflict() {
        pendingTransferConflict = nil
        conflictRenameText = ""
    }

    func overwritePendingConflict() {
        guard let conflict = pendingTransferConflict else { return }
        pendingTransferConflict = nil
        conflictRenameText = ""
        enqueueTransfer(conflict.job, profile: conflict.profile)
    }

    func renameAndRunPendingConflict() {
        guard let conflict = pendingTransferConflict else { return }
        let name = conflictRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var renamed = conflict.job
        switch renamed.direction {
        case .upload:
            renamed.destinationPath = remotePathAppending(session.remotePath, name)
        case .download:
            renamed.destinationPath = URL(fileURLWithPath: session.localPath).appendingPathComponent(name).path
        }
        pendingTransferConflict = nil
        conflictRenameText = ""
        enqueueTransfer(renamed, profile: conflict.profile)
    }

    private func suggestedConflictName(for original: String) -> String {
        let url = URL(fileURLWithPath: original)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        return ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)"
    }

    private func remotePathAppending(_ base: String, _ name: String) -> String {
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return trimmed.isEmpty ? "/\(name)" : "\(trimmed)/\(name)"
    }

    private func replaceTransferJob(_ job: TransferJob) {
        if let index = transferJobs.firstIndex(where: { $0.id == job.id }) {
            transferJobs[index] = job
        } else {
            transferJobs.insert(job, at: 0)
        }
    }

    private func saveActiveTabSnapshot() {
        guard let selectedTabID, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs[index].session = session
        tabs[index].localItems = localItems
        tabs[index].remoteItems = remoteItems
        tabs[index].selectedFile = selectedFile
        if let profile = selectedProfile {
            tabs[index].title = profile.displayName
        } else if session.remotePath != "/" {
            tabs[index].title = session.remotePath
        } else {
            tabs[index].title = "New Connection"
        }
    }

    func selectTab(_ tabID: WorkspaceTab.ID) {
        saveActiveTabSnapshot()
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        selectedTabID = tabID
        session = tab.session
        localItems = tab.localItems
        remoteItems = tab.remoteItems
        selectedFile = tab.selectedFile
    }

    func clearCompletedTransfers() {
        transferJobs.removeAll { job in
            if case .succeeded = job.status { return true }
            return false
        }
    }

    func clearFailedTransfers() {
        transferJobs.removeAll { job in
            if case .failed = job.status { return true }
            return false
        }
    }

    func retryFailedTransfers() {
        let failedJobs = transferJobs.filter { job in
            if case .failed = job.status { return true }
            return false
        }
        for var job in failedJobs {
            guard let profile = transferProfiles[job.id] ?? activeProfile else { continue }
            job.status = .queued
            job.startedAt = nil
            job.finishedAt = nil
            enqueueTransfer(job, profile: profile)
        }
    }

    func cancelActiveTransfers() {
        let activeIDs = transferJobs.compactMap { job -> TransferJobID? in
            if case .running = job.status { return job.id }
            return nil
        }
        transferJobs = transferJobs.map { job in
            guard case .running = job.status else { return job }
            var cancelled = job
            cancelled.status = .cancelled
            cancelled.finishedAt = Date()
            return cancelled
        }
        Task {
            for id in activeIDs {
                try? await transferClientForCurrentPreference().cancel(id: id)
            }
        }
        processTransferQueue()
    }

    func cancelTransfer(id: TransferJobID) {
        guard let index = transferJobs.firstIndex(where: { $0.id == id }) else { return }
        switch transferJobs[index].status {
        case .queued:
            transferJobs[index].status = .cancelled
            transferJobs[index].finishedAt = Date()
            transferProfiles[id] = nil
            processTransferQueue()
        case .running:
            transferJobs[index].status = .cancelled
            transferJobs[index].finishedAt = Date()
            transferProfiles[id] = nil
            Task {
                try? await transferClientForCurrentPreference().cancel(id: id)
                await MainActor.run {
                    self.processTransferQueue()
                }
            }
        case .succeeded, .failed, .cancelled:
            break
        }
    }

    func newTab() {
        saveActiveTabSnapshot()
        let tab = WorkspaceTab()
        tabs.append(tab)
        selectTab(tab.id)
    }

    func closeSelectedTab() {
        guard tabs.count > 1, let selectedTabID else { return }
        tabs.removeAll { $0.id == selectedTabID }
        if let first = tabs.first {
            selectTab(first.id)
        }
    }

    var activeProfile: ServerProfile? {
        if let selectedProfile {
            return selectedProfile
        }
        if let serverID = session.serverID {
            return profiles.first { $0.id == serverID }
        }
        return nil
    }

    private func remoteClientForCurrentPreference() -> RemoteFileSystemClient {
        switch preferences.remoteBackendKind {
        case .systemSSH:
            remoteFileSystem
        case .nativeSwiftExperimental:
            nativeRemoteFileSystem
        }
    }

    private func transferClientForCurrentPreference() -> TransferClient {
        switch preferences.remoteBackendKind {
        case .systemSSH:
            transferClient
        case .nativeSwiftExperimental:
            nativeTransferClient
        }
    }
}

private extension TransferJob {
    var isQueued: Bool {
        if case .queued = status { return true }
        return false
    }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }
}

struct TransferConflict: Identifiable {
    var id = UUID()
    var job: TransferJob
    var profile: ServerProfile
    var existingPath: String
}

struct FileOperationPrompt: Identifiable, Equatable {
    enum Kind: Equatable {
        case createFolder
        case rename(FileItem)
    }

    var id = UUID()
    var kind: Kind
    var source: FileSource

    var title: String {
        switch kind {
        case .createFolder:
            "New \(source.rawValue.capitalized) Folder"
        case .rename:
            "Rename Item"
        }
    }
}

struct PendingHostTrust: Identifiable, Equatable {
    var id: String { "\(host):\(port):\(algorithm):\(fingerprint)" }
    var host: String
    var port: Int
    var algorithm: String
    var fingerprint: String
    var knownHostsLine: String
}

struct ServerProfileDraft: Identifiable, Equatable {
    enum AuthKind: String, CaseIterable, Identifiable {
        case agent = "SSH Agent"
        case password = "Password"
        case privateKey = "Private Key"
        case none = "None"

        var id: String { rawValue }
    }

    var id: ServerProfileID
    var displayName: String
    var host: String
    var port: Int
    var protocolKind: TransferProtocolKind
    var username: String
    var authKind: AuthKind
    var privateKeyPath: String
    var password: String
    var passphrase: String
    var storePassphrase: Bool
    var remoteDefaultPath: String
    var localDefaultPath: String
    var notes: String
    var tags: String
    var isFavorite: Bool
    var groupName: String
    var createdAt: Date

    init() {
        self.id = ServerProfileID()
        self.displayName = ""
        self.host = ""
        self.port = TransferProtocolKind.sftp.defaultPort
        self.protocolKind = .sftp
        self.username = NSUserName()
        self.authKind = .agent
        self.privateKeyPath = "~/.ssh/id_ed25519"
        self.password = ""
        self.passphrase = ""
        self.storePassphrase = false
        self.remoteDefaultPath = "/"
        self.localDefaultPath = FileManager.default.homeDirectoryForCurrentUser.path
        self.notes = ""
        self.tags = ""
        self.isFavorite = false
        self.groupName = ""
        self.createdAt = Date()
    }

    init(profile: ServerProfile) {
        self.id = profile.id
        self.displayName = profile.displayName
        self.host = profile.host
        self.port = profile.port
        self.protocolKind = profile.protocolKind
        self.username = profile.username
        self.remoteDefaultPath = profile.remoteDefaultPath
        self.localDefaultPath = profile.localDefaultPath
        self.notes = profile.notes
        self.tags = profile.tags.joined(separator: ", ")
        self.isFavorite = profile.isFavorite
        self.groupName = profile.groupName ?? ""
        self.createdAt = profile.createdAt

        switch profile.authenticationMethod {
        case .agent:
            self.authKind = .agent
            self.privateKeyPath = "~/.ssh/id_ed25519"
            self.password = ""
            self.passphrase = ""
            self.storePassphrase = false
        case .password:
            self.authKind = .password
            self.privateKeyPath = "~/.ssh/id_ed25519"
            self.password = ""
            self.passphrase = ""
            self.storePassphrase = false
        case .privateKey(let path, _):
            self.authKind = .privateKey
            self.privateKeyPath = path
            self.password = ""
            self.passphrase = ""
            self.storePassphrase = false
        case .none:
            self.authKind = .none
            self.privateKeyPath = "~/.ssh/id_ed25519"
            self.password = ""
            self.passphrase = ""
            self.storePassphrase = false
        }
    }

    func makeProfile() -> ServerProfile {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let credentialAccount = "\(trimmedUsername)@\(trimmedHost)"
        let authenticationMethod: AuthenticationMethod
        switch authKind {
        case .agent:
            authenticationMethod = .agent
        case .password:
            authenticationMethod = .password(CredentialReference(service: "app.driftline.credentials", account: credentialAccount))
        case .privateKey:
            let passphraseReference = storePassphrase
                ? CredentialReference(service: "app.driftline.private-key-passphrase", account: credentialAccount)
                : nil
            authenticationMethod = .privateKey(path: privateKeyPath, passphrase: passphraseReference)
        case .none:
            authenticationMethod = .none
        }

        return ServerProfile(
            id: id,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            host: trimmedHost,
            port: port,
            protocolKind: protocolKind,
            username: trimmedUsername,
            authenticationMethod: authenticationMethod,
            remoteDefaultPath: remoteDefaultPath.isEmpty ? "/" : remoteDefaultPath,
            localDefaultPath: localDefaultPath.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : localDefaultPath,
            notes: notes,
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            isFavorite: isFavorite,
            groupName: groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : groupName.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

struct WorkspaceTab: Identifiable {
    var id = UUID()
    var title = "New Connection"
    var session = ConnectionSession(state: .disconnected, protocolKind: .sftp)
    var localItems: [FileItem] = []
    var remoteItems: [FileItem] = []
    var selectedFile: FileItem?
}

struct SidebarItem: Identifiable, Hashable {
    var id: String
    var title: String
    var systemImage: String

    static let quickConnect = SidebarItem(id: "quick-connect", title: "Quick Connect", systemImage: "bolt.horizontal")
    static let favorites = SidebarItem(id: "favorites", title: "Favorites", systemImage: "star")
    static let recents = SidebarItem(id: "recents", title: "Recent Servers", systemImage: "clock")
    static let bookmarks = SidebarItem(id: "bookmarks", title: "Bookmarks", systemImage: "bookmark")
    static let all: [SidebarItem] = [.quickConnect, .favorites, .recents, .bookmarks]
}
