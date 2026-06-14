import AppKit
import DriftlineCore
import SwiftUI

@main
struct DriftlineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Driftline", id: "main") {
            ContentView(model: self.model)
                .frame(minWidth: 1180, minHeight: 720)
        }
        .commands {
            DriftlineCommands(model: self.model)
        }

        Settings {
            SettingsView(model: self.model)
                .onChange(of: self.model.preferences) { _, _ in
                    AppIconController.apply(self.model.preferences.appIconVariant)
                    AppThemeController.apply(self.model.preferences.appThemeVariant)
                    self.model.savePreferences()
                }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
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
    var selectedLocalFile: FileItem?
    var selectedRemoteFile: FileItem?
    var selectedLocalFileIDs: Set<String> = []
    var selectedRemoteFileIDs: Set<String> = []
    var selectedLocalFiles: [FileItem] = []
    var selectedRemoteFiles: [FileItem] = []
    var copiedFiles: [FileItem] = []
    var activePane: FileSource = .local
    var profileDraft: ServerProfileDraft?
    var profileEditorError: String?
    var isConnecting = false
    var pendingHostTrust: PendingHostTrust?
    var fileOperationPrompt: FileOperationPrompt?
    var fileOperationText = ""
    var pendingDeleteItem: FileItem?
    var pendingTransferConflict: TransferConflict?
    var queuedTransferConflicts: [TransferConflict] = []
    var conflictRenameText = ""
    var conflictApplyToRemaining = false
    var syncPreview: SyncPreview?
    var bookmarks: [ServerBookmark] = []
    var recents: [RecentServer] = []
    var connectAfterSavingDraft = false
    var showViewOptions = false
    var showAbout = false
    var pendingUpdate: AppUpdate?
    var isCheckingForUpdates = false
    var pendingCloseTabID: WorkspaceTab.ID?

    var pendingCloseTab: WorkspaceTab? {
        guard let id = pendingCloseTabID else { return nil }
        return self.tabs.first { $0.id == id }
    }

    var statusMessage: ToastMessage?
    var userAlert: UserAlert?
    var footerMessage: String?
    var hasInitialLoadFailed = false
    var transferJobs: [TransferJob] = []
    var transferProfiles: [TransferJobID: ServerProfile] = [:]
    var profiles: [ServerProfile] = []
    var session = ConnectionSession(state: .disconnected, protocolKind: .sftp)
    var transferStats: TransferStats {
        TransferStatsCalculator.calculate(from: self.transferJobs)
    }

    var selectedFile: FileItem? {
        switch self.activePane {
        case .local:
            self.selectedLocalFiles.first ?? self.selectedLocalFile
        case .remote:
            self.selectedRemoteFiles.first ?? self.selectedRemoteFile
        }
    }

    var lastConnectionDisplay: String {
        guard let connectedAt = session.connectedAt else { return self.loc("common.none") }
        return connectedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private let localFileSystem: LocalFileSystemClient
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
    private let diagnosticsRecorder: DiagnosticsRecorder
    private let notificationController: AppNotificationControlling
    private var didPerformStartupUpdateCheck = false

    init(
        profileRepository: ServerProfileRepository = JSONServerProfileRepository(),
        preferencesRepository: ViewPreferencesRepository = JSONViewPreferencesRepository(),
        transferHistoryRepository: TransferHistoryRepository = JSONTransferHistoryRepository(),
        bookmarkRepository: ServerBookmarkRepository = JSONServerBookmarkRepository(),
        recentRepository: RecentServerRepository = JSONRecentServerRepository(),
        localFileSystem: LocalFileSystemClient = FoundationLocalFileSystemClient(),
        remoteFileSystem: RemoteFileSystemClient = SystemSFTPClient.secureDefault(),
        nativeRemoteFileSystem: RemoteFileSystemClient? = nil,
        transferClient: TransferClient = SystemRsyncTransferClient(),
        nativeTransferClient: TransferClient? = nil,
        hostTrustStore: HostTrustStore = JSONHostTrustStore(),
        knownHostsFile: ManagedKnownHostsFile = ManagedKnownHostsFile(),
        terminalLauncher: TerminalLaunching = SystemTerminalLauncher(),
        credentialStore: CredentialStore = KeychainCredentialStore(),
        diagnosticsRecorder: DiagnosticsRecorder = DiagnosticsRecorder(),
        notificationController: AppNotificationControlling = AppNotificationController()
    ) {
        self.localFileSystem = localFileSystem
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
        self.diagnosticsRecorder = diagnosticsRecorder
        self.notificationController = notificationController
        self.selectedTabID = self.tabs.first?.id
        Task { await self.loadInitialState() }
    }

    func loadInitialState() async {
        await self.notificationController.requestPermissionIfNeeded()
        do {
            self.preferences = try await self.preferencesRepository.load()
            self.detectAndApplyLanguage()
            AppIconController.apply(self.preferences.appIconVariant)
            AppThemeController.apply(self.preferences.appThemeVariant)
            self.profiles = try await self.profileRepository.list()
            self.bookmarks = try await self.bookmarkRepository.list()
            self.recents = try await self.recentRepository.list(limit: 10)
            self.transferJobs = try await self.transferHistoryRepository.list(limit: 100)
            self.consumeLaunchRequest()
            await self.refreshLocal()
            await self.performStartupUpdateCheckIfNeeded()
        } catch {
            self.recordError(error, category: "startup")
            self.session.lastErrorMessage = error.localizedDescription
            self.footerMessage = error.localizedDescription
            self.hasInitialLoadFailed = true
        }
    }

    func retryInitialLoad() {
        guard self.hasInitialLoadFailed else { return }
        self.hasInitialLoadFailed = false
        self.footerMessage = nil
        Task { await self.loadInitialState() }
    }

    private func consumeLaunchRequest() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--driftline-open"), args.indices.contains(index + 1) {
            if args.contains("--driftline-new-tab") {
                self.newTab()
            }
            self.session.localPath = args[index + 1]
            Task { await self.refreshLocal() }
            return
        }
        if let index = args.firstIndex(of: "--driftline-bookmark"), args.indices.contains(index + 1) {
            if args.contains("--driftline-new-tab") {
                self.newTab()
            }
            self.openBookmark(named: args[index + 1])
            return
        }
        if let request = try? CLIRequestStore.consume() {
            if request.openInNewTab {
                self.newTab()
            }
            switch request.intent {
            case let .openPath(path):
                self.session.localPath = path
                Task { await self.refreshLocal() }
            case let .openBookmark(name):
                self.openBookmark(named: name)
            }
        }
    }

    func performStartupUpdateCheckIfNeeded() async {
        guard !self.didPerformStartupUpdateCheck else { return }
        self.didPerformStartupUpdateCheck = true
        guard self.preferences.checkForUpdatesOnStartup else { return }
        await self.checkForUpdatesNow(showNoUpdateMessage: false)
    }

    func checkForUpdates(showNoUpdateMessage: Bool) {
        Task {
            await self.checkForUpdatesNow(showNoUpdateMessage: showNoUpdateMessage)
        }
    }

    private func checkForUpdatesNow(showNoUpdateMessage: Bool) async {
        guard !self.isCheckingForUpdates else { return }
        self.isCheckingForUpdates = true
        defer { self.isCheckingForUpdates = false }

        do {
            let checker = GitHubUpdateChecker(currentVersion: AppMetadata.shortVersion)
            let update = try await checker.latestUpdate()
            if update.isNewer {
                self.pendingUpdate = update
                self.notifyInBackground(
                    title: self.loc("update.notificationTitle"),
                    body: self.loc("update.notificationBody", update.latestVersion),
                    identifier: "update-\(update.latestVersion)"
                )
                self.recordDiagnostic(level: .info, category: "updates", message: "Update available: \(update.latestVersion)")
            } else if showNoUpdateMessage {
                self.statusMessage = ToastMessage(text: self.loc("toast.upToDate"))
            }
        } catch {
            self.recordError(error, category: "updates")
            if showNoUpdateMessage {
                self.userAlert = UserAlert(title: self.loc("alert.checkUpdatesTitle"), message: error.localizedDescription)
            }
        }
    }

    func openPendingUpdateDownload() {
        guard let pendingUpdate else { return }
        NSWorkspace.shared.open(pendingUpdate.assetURL ?? pendingUpdate.releaseURL)
        self.pendingUpdate = nil
    }

    func dismissPendingUpdate() {
        self.pendingUpdate = nil
    }

    func revealDiagnosticsLog() {
        Task {
            await self.diagnosticsRecorder.record(level: .info, category: "diagnostics", message: "Diagnostics log revealed.")
            let fileURL = await self.diagnosticsRecorder.fileURL
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        }
    }

    private func recordError(_ error: Error, category: String) {
        self.recordDiagnostic(level: .error, category: category, message: error.localizedDescription)
    }

    private func recordDiagnostic(level: DiagnosticLevel, category: String, message: String) {
        Task {
            await self.diagnosticsRecorder.record(level: level, category: category, message: message)
        }
    }

    private func notifyInBackground(title: String, body: String, identifier: String = UUID().uuidString) {
        self.notificationController.notifyIfBackground(
            isEnabled: self.preferences.backgroundNotificationsEnabled,
            title: title,
            body: body,
            identifier: identifier
        )
    }

    func refreshLocal() async {
        do {
            self.localItems = try await self.localFileSystem.listDirectory(at: self.session.localPath, preferences: self.preferences.fileList)
            self.saveActiveTabSnapshot()
        } catch {
            self.recordError(error, category: "local.list")
            self.localItems = []
            self.session.lastErrorMessage = error.localizedDescription
            self.footerMessage = error.localizedDescription
        }
    }

    func navigateLocal(to item: FileItem) {
        guard item.source == .local else { return }
        if item.kind == .folder {
            self.navigateLocal(toPath: item.path)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
        }
    }

    func navigateLocal(toPath path: String) {
        self.session.localPath = path
        Task { await self.refreshLocal() }
    }

    func navigateRemote(to item: FileItem) {
        guard item.source == .remote, item.kind == .folder else { return }
        self.navigateRemote(toPath: item.path)
    }

    func navigateRemote(toPath path: String) {
        self.session.remotePath = path.isEmpty ? "/" : path
        Task { await self.refreshRemote() }
    }

    func selectItems(_ items: [FileItem], in source: FileSource) {
        switch source {
        case .local:
            self.selectedLocalFileIDs = Set(items.map(\.id))
            self.selectedLocalFiles = items
            self.selectedLocalFile = items.first
            self.selectedRemoteFileIDs = []
            self.selectedRemoteFiles = []
            self.selectedRemoteFile = nil
        case .remote:
            self.selectedRemoteFileIDs = Set(items.map(\.id))
            self.selectedRemoteFiles = items
            self.selectedRemoteFile = items.first
            self.selectedLocalFileIDs = []
            self.selectedLocalFiles = []
            self.selectedLocalFile = nil
        }
        self.activePane = source
    }

    func loadChildren(of item: FileItem, completion: @escaping ([FileItem]) -> Void) {
        Task {
            do {
                switch item.source {
                case .local:
                    let children = try await self.localFileSystem.listDirectory(at: item.path, preferences: self.preferences.fileList)
                    completion(children)
                case .remote:
                    guard let profile = self.activeProfile else {
                        completion([])
                        return
                    }
                    let children = try await self.remoteClientForCurrentPreference().listDirectory(
                        at: item.path,
                        profile: profile,
                        session: self.session,
                        preferences: self.preferences.fileList
                    )
                    completion(children)
                }
            } catch {
                self.recordError(error, category: "browser.children")
                self.footerMessage = error.localizedDescription
                completion([])
            }
        }
    }

    func copySelectedItems() {
        switch self.activePane {
        case .local:
            self.copyItems(self.selectedLocalFiles)
        case .remote:
            self.copyItems(self.selectedRemoteFiles)
        }
    }

    func copyItems(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        self.copiedFiles = items
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(items.map(\.path).joined(separator: "\n"), forType: .string)
        self.statusMessage = ToastMessage(text: items.count == 1 ? self.loc("toast.copiedSingle", items[0].name) : self.loc("toast.copiedMulti", items.count))
    }

    func pasteCopiedItemsIntoActivePane() {
        self.pasteCopiedItems(into: self.activePane)
    }

    func pasteCopiedItems(into destination: FileSource) {
        guard !self.copiedFiles.isEmpty else { return }
        let source = self.copiedFiles[0].source
        if source != destination {
            _ = self.transferDroppedItems(self.copiedFiles, to: destination)
            return
        }

        switch destination {
        case .local:
            self.copyLocalItems(self.copiedFiles)
        case .remote:
            self.userAlert = UserAlert(title: self.loc("alert.unsupportedTitle"), message: self.loc("alert.unsupportedMsg"))
        }
    }

    func prepareSyncPreview() {
        guard self.session.state == .connected else {
            self.userAlert = UserAlert(title: self.loc("alert.notConnectedTitle"), message: self.loc("alert.notConnectedMsg"))
            return
        }
        self.syncPreview = SyncPreview(localPath: self.session.localPath, remotePath: self.session.remotePath, localItems: self.localItems, remoteItems: self.remoteItems)
    }

    func uploadSyncItems(_ items: [FileItem]) {
        self.syncPreview = nil
        self.uploadItems(items)
    }

    func downloadSyncItems(_ items: [FileItem]) {
        self.syncPreview = nil
        self.downloadItems(items)
    }

    func runSyncPlan(_ plan: SyncRunPlan) {
        self.syncPreview = nil
        let total = plan.uploads.count + plan.downloads.count
        guard total > 0 else { return }
        self.uploadItems(plan.uploads, conflictPolicy: plan.conflictPolicy)
        self.downloadItems(plan.downloads, conflictPolicy: plan.conflictPolicy)
        self.statusMessage = ToastMessage(text: total == 1 ? self.loc("toast.syncStartedSingle") : self.loc("toast.syncStartedMulti", total))
    }

    private func copyLocalItems(_ items: [FileItem]) {
        Task {
            var copiedCount = 0
            for item in items where item.source == .local {
                do {
                    let destination = self.uniqueLocalCopyDestination(for: item)
                    try FileManager.default.copyItem(atPath: item.path, toPath: destination.path)
                    copiedCount += 1
                } catch {
                    self.recordError(error, category: "local.copy")
                    self.userAlert = UserAlert(title: self.loc("alert.copyFailedTitle"), message: error.localizedDescription)
                    return
                }
            }
            await self.refreshLocal()
            self.statusMessage = ToastMessage(text: copiedCount == 1 ? self.loc("toast.copiedSingle", copiedCount) : self.loc("toast.copiedMulti", copiedCount))
        }
    }

    private func uniqueLocalCopyDestination(for item: FileItem) -> URL {
        let sourceURL = URL(fileURLWithPath: item.path)
        let parent = sourceURL.deletingLastPathComponent()
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let firstName = ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)"
        var candidate = parent.appendingPathComponent(firstName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) copy \(index)" : "\(base) copy \(index).\(ext)"
            candidate = parent.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }

    func navigateLocalParent() {
        let parent = URL(fileURLWithPath: session.localPath).deletingLastPathComponent().path
        guard parent != self.session.localPath else { return }
        self.session.localPath = parent
        Task { await self.refreshLocal() }
    }

    func navigateRemoteParent() {
        guard self.session.remotePath != "/" else { return }
        let parent = URL(fileURLWithPath: session.remotePath).deletingLastPathComponent().path
        self.session.remotePath = parent.isEmpty ? "/" : parent
        Task { await self.refreshRemote() }
    }

    func beginQuickConnect() {
        self.connectAfterSavingDraft = true
        self.beginCreatingProfile()
    }

    func connectToSelectedServer() {
        Task { await self.connectSelectedServer() }
    }

    func connectSelectedServer() async {
        guard let profile = selectedProfile else {
            self.userAlert = UserAlert(title: self.loc("alert.noServerTitle"), message: self.loc("alert.noServerMsg"))
            self.beginQuickConnect()
            return
        }
        await self.connect(profile)
    }

    private func connect(_ profile: ServerProfile) async {
        self.isConnecting = true
        self.useNativeBackendIfNeeded(for: profile)
        self.session = ConnectionSession(serverID: profile.id, state: .connecting, protocolKind: profile.protocolKind, localPath: profile.localDefaultPath, remotePath: profile.remoteDefaultPath)
        do {
            let client = self.remoteClientForCurrentPreference()
            self.session = try await client.connect(to: profile)
            self.remoteItems = try await client.listDirectory(at: self.session.remotePath, profile: profile, session: self.session, preferences: self.preferences.fileList)
            try await self.recentRepository.record(RecentServer(
                profileID: profile.id,
                displayName: profile.displayName,
                host: profile.host,
                protocolKind: profile.protocolKind,
                localPath: self.session.localPath,
                remotePath: self.session.remotePath
            ), limit: 10)
            self.recents = try await self.recentRepository.list(limit: 10)
            self.saveActiveTabSnapshot()
            self.isConnecting = false
        } catch {
            self.recordError(error, category: "connection")
            self.remoteItems = []
            if case let RemoteClientError.hostNotTrusted(host, port, algorithm, fingerprint, knownHostsLine) = error {
                self.pendingHostTrust = PendingHostTrust(host: host, port: port, algorithm: algorithm, fingerprint: fingerprint, knownHostsLine: knownHostsLine)
            }
            self.session.state = .failed(message: error.localizedDescription)
            self.session.lastErrorMessage = error.localizedDescription
            self.footerMessage = error.localizedDescription
            self.isConnecting = false
        }
    }

    private func useNativeBackendIfNeeded(for profile: ServerProfile) {
        guard case .password = profile.authenticationMethod,
              self.preferences.remoteBackendKind != .nativeSwiftExperimental
        else { return }
        self.preferences.remoteBackendKind = .nativeSwiftExperimental
        self.footerMessage = self.loc("toast.nativeSSHSwitch")
        self.savePreferences()
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
                try await self.hostTrustStore.trust(record)
                try await self.knownHostsFile.trust(record)
                self.pendingHostTrust = nil
                await self.connectSelectedServer()
            } catch {
                self.recordError(error, category: "host-trust")
                self.session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func refreshRemote() async {
        guard let profile = activeProfile, session.state == .connected else { return }
        do {
            self.remoteItems = try await self.remoteClientForCurrentPreference().listDirectory(at: self.session.remotePath, profile: profile, session: self.session, preferences: self.preferences.fileList)
            self.saveActiveTabSnapshot()
        } catch {
            self.notifyInBackground(
                title: self.loc("notification.serverDisconnectedTitle"),
                body: self.loc("notification.serverDisconnectedBody", profile.displayName),
                identifier: "server-disconnected-\(profile.id.rawValue.uuidString)"
            )
            self.recordError(error, category: "remote.list")
            self.session.state = .failed(message: error.localizedDescription)
            self.session.lastErrorMessage = error.localizedDescription
            self.footerMessage = error.localizedDescription
        }
    }

    func disconnect() {
        let sessionToDisconnect = self.session
        self.session.state = .disconnected
        self.remoteItems = []
        self.saveActiveTabSnapshot()
        Task {
            try? await self.remoteClientForCurrentPreference().disconnect(session: sessionToDisconnect)
        }
    }

    func setLanguage(_ language: SupportedLanguage) {
        self.preferences.localizedLanguage = language
        self.preferences.hasSetLanguageExplicitly = true
        LocalizationManager.shared.setLanguage(language)
        self.savePreferences()
    }

    private func detectAndApplyLanguage() {
        let detected = LocalizationManager.shared.detectSystemLanguage()
        LocalizationManager.shared.setLanguage(self.preferences.localizedLanguage)
        if !self.preferences.hasSetLanguageExplicitly, self.preferences.localizedLanguage != detected {
            self.preferences.localizedLanguage = detected
            LocalizationManager.shared.setLanguage(detected)
            self.savePreferences()
        }
    }

    func savePreferences() {
        let current = self.preferences
        Task {
            try? await self.preferencesRepository.save(current)
        }
    }

    var selectedProfile: ServerProfile? {
        guard let selectedSidebarItem else { return nil }
        return self.profiles.first { $0.id.rawValue.uuidString == selectedSidebarItem }
    }

    func toggleSelectedFavorite() {
        guard var selectedProfile else { return }
        selectedProfile.isFavorite.toggle()
        Task {
            do {
                try await self.profileRepository.save(selectedProfile)
                self.profiles = try await self.profileRepository.list()
                self.statusMessage = ToastMessage(text: selectedProfile.isFavorite ? self.loc("toast.favoriteAdded") : self.loc("toast.favoriteRemoved"))
            } catch {
                self.recordError(error, category: "profile.favorite")
                self.userAlert = UserAlert(title: self.loc("alert.favoriteFailedTitle"), message: error.localizedDescription)
            }
        }
    }

    func saveCurrentConnectionAsBookmark() {
        guard let profile = activeProfile else { return }
        let bookmark = ServerBookmark(
            profileID: profile.id,
            name: "\(profile.displayName): \(self.session.remotePath)",
            localPath: self.session.localPath,
            remotePath: self.session.remotePath
        )
        Task {
            do {
                try await self.bookmarkRepository.save(bookmark)
                self.bookmarks = try await self.bookmarkRepository.list()
                self.statusMessage = ToastMessage(text: self.loc("toast.bookmarkSaved"))
            } catch {
                self.recordError(error, category: "bookmark.save")
                self.userAlert = UserAlert(title: self.loc("alert.bookmarkSaveFailedTitle"), message: error.localizedDescription)
            }
        }
    }

    func openBookmark(_ bookmark: ServerBookmark) {
        guard self.profiles.contains(where: { $0.id == bookmark.profileID }) else { return }
        self.selectedSidebarItem = bookmark.profileID.rawValue.uuidString
        self.session.localPath = bookmark.localPath
        self.session.remotePath = bookmark.remotePath
        Task {
            await self.refreshLocal()
            await self.connectSelectedServer()
        }
    }

    func openBookmark(named name: String) {
        guard let bookmark = self.bookmarks.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            self.userAlert = UserAlert(title: self.loc("alert.bookmarkNotFoundTitle"), message: self.loc("alert.bookmarkNotFoundMsg", name))
            return
        }
        self.openBookmark(bookmark)
    }

    func openRecent(_ recent: RecentServer) {
        self.selectedSidebarItem = recent.profileID.rawValue.uuidString
        self.session.localPath = recent.localPath
        self.session.remotePath = recent.remotePath
        Task {
            await self.refreshLocal()
            await self.connectSelectedServer()
        }
    }

    func reconnectLastServer() {
        if let recent = recents.first {
            self.openRecent(recent)
        } else {
            self.beginQuickConnect()
        }
    }

    func beginCreatingProfile() {
        self.connectAfterSavingDraft = false
        self.profileEditorError = nil
        self.profileDraft = ServerProfileDraft()
    }

    func beginEditingSelectedProfile() {
        guard let selectedProfile else { return }
        self.profileEditorError = nil
        self.profileDraft = ServerProfileDraft(profile: selectedProfile)
    }

    func saveProfileDraft() {
        guard let draft = profileDraft else { return }
        do {
            let profile = draft.makeProfile()
            try ServerProfileValidator.validate(profile)
            Task {
                do {
                    let previousProfiles = self.profiles
                    let previousProfile = previousProfiles.first { $0.id == profile.id }
                    try await self.saveCredentialSecrets(from: draft, profile: profile, previousProfile: previousProfile)
                    try await self.profileRepository.save(profile)
                    self.profiles = try await self.profileRepository.list()
                    try await self.deleteUnusedCredentialReferences(from: previousProfile.map { [$0] } ?? [], keeping: self.profiles)
                    self.selectedSidebarItem = profile.id.rawValue.uuidString
                    self.profileDraft = nil
                    self.profileEditorError = nil
                    if self.connectAfterSavingDraft {
                        self.connectAfterSavingDraft = false
                        await self.connect(profile)
                    }
                } catch {
                    self.recordError(error, category: "profile.save")
                    self.profileEditorError = error.localizedDescription
                }
            }
        } catch {
            self.recordError(error, category: "profile.validate")
            self.profileEditorError = error.localizedDescription
        }
    }

    private func saveCredentialSecrets(from draft: ServerProfileDraft, profile: ServerProfile, previousProfile: ServerProfile?) async throws {
        switch profile.authenticationMethod {
        case let .password(reference):
            if !draft.password.isEmpty {
                try await self.credentialStore.saveString(draft.password, reference: reference)
            } else {
                try await self.copyCredentialIfNeeded(from: self.passwordReference(for: previousProfile), to: reference)
            }
        case let .privateKey(_, passphraseReference):
            if let passphraseReference, !draft.passphrase.isEmpty {
                try await self.credentialStore.saveString(draft.passphrase, reference: passphraseReference)
            } else if let passphraseReference {
                try await self.copyCredentialIfNeeded(from: self.passphraseReference(for: previousProfile), to: passphraseReference)
            }
        case .agent, .none:
            break
        }
    }

    private func copyCredentialIfNeeded(from previousReference: CredentialReference?, to reference: CredentialReference) async throws {
        guard let previousReference, previousReference != reference else { return }
        guard let secret = try await self.credentialStore.read(reference: previousReference) else { return }
        try await self.credentialStore.save(secret: secret, reference: reference)
    }

    private func passwordReference(for profile: ServerProfile?) -> CredentialReference? {
        guard let profile, case let .password(reference) = profile.authenticationMethod else { return nil }
        return reference
    }

    private func passphraseReference(for profile: ServerProfile?) -> CredentialReference? {
        guard let profile, case let .privateKey(_, reference?) = profile.authenticationMethod else { return nil }
        return reference
    }

    func duplicateSelectedProfile() {
        guard let selectedProfile else { return }
        let copy = selectedProfile.duplicated()
        Task {
            do {
                try await self.profileRepository.save(copy)
                self.profiles = try await self.profileRepository.list()
                self.selectedSidebarItem = copy.id.rawValue.uuidString
            } catch {
                self.recordError(error, category: "profile.duplicate")
                self.session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func deleteSelectedProfile() {
        guard let selectedProfile else { return }
        Task {
            do {
                try await self.profileRepository.delete(id: selectedProfile.id)
                self.profiles = try await self.profileRepository.list()
                try await self.deleteDependentNavigationRecords(for: selectedProfile.id)
                try await self.deleteUnusedCredentialReferences(from: [selectedProfile], keeping: self.profiles)
                self.selectedSidebarItem = nil
                if self.session.serverID == selectedProfile.id {
                    self.disconnect()
                }
            } catch {
                self.recordError(error, category: "profile.delete")
                self.session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteDependentNavigationRecords(for profileID: ServerProfileID) async throws {
        let staleBookmarks = self.bookmarks.filter { $0.profileID == profileID }
        for bookmark in staleBookmarks {
            try await self.bookmarkRepository.delete(id: bookmark.id)
        }
        try await self.recentRepository.delete(profileID: profileID)
        self.bookmarks = try await self.bookmarkRepository.list()
        self.recents = try await self.recentRepository.list(limit: 10)
    }

    private func deleteUnusedCredentialReferences(from oldProfiles: [ServerProfile], keeping currentProfiles: [ServerProfile]) async throws {
        let currentReferences = Set(currentProfiles.flatMap { self.credentialReferences(for: $0) })
        let staleReferences = Set(oldProfiles.flatMap { self.credentialReferences(for: $0) }).subtracting(currentReferences)
        for reference in staleReferences {
            try await self.credentialStore.delete(reference: reference)
        }
    }

    private func credentialReferences(for profile: ServerProfile) -> [CredentialReference] {
        switch profile.authenticationMethod {
        case let .password(reference):
            [reference]
        case let .privateKey(_, passphraseReference):
            passphraseReference.map { [$0] } ?? []
        case .agent, .none:
            []
        }
    }

    func beginCreateFolder(source: FileSource) {
        self.fileOperationText = self.loc("file.newFolder")
        self.fileOperationPrompt = FileOperationPrompt(kind: .createFolder, source: source)
    }

    func beginRenameSelectedItem(source: FileSource? = nil) {
        let source = source ?? self.activePane
        guard let selectedFile = self.selectedFile(in: source) else { return }
        self.activePane = source
        self.fileOperationText = selectedFile.name
        self.fileOperationPrompt = FileOperationPrompt(kind: .rename(selectedFile), source: selectedFile.source)
    }

    func requestDeleteSelectedItem(source: FileSource? = nil) {
        let source = source ?? self.activePane
        guard let selectedFile = self.selectedFile(in: source) else { return }
        self.activePane = source
        if self.preferences.confirmBeforeDelete {
            self.pendingDeleteItem = selectedFile
        } else {
            self.deleteItem(selectedFile)
        }
    }

    func commitFileOperationPrompt() {
        guard let prompt = fileOperationPrompt else { return }
        let value = self.fileOperationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        switch prompt.kind {
        case .createFolder:
            self.createFolder(named: value, source: prompt.source)
        case let .rename(item):
            self.renameItem(item, to: value)
        }
        self.fileOperationPrompt = nil
        self.fileOperationText = ""
    }

    func deletePendingItem() {
        guard let pendingDeleteItem else { return }
        self.deleteItem(pendingDeleteItem)
        self.pendingDeleteItem = nil
    }

    private func createFolder(named name: String, source: FileSource) {
        Task {
            do {
                switch source {
                case .local:
                    try await self.localFileSystem.createFolder(named: name, in: self.session.localPath)
                    await self.refreshLocal()
                case .remote:
                    guard let profile = activeProfile else { return }
                    try await self.remoteClientForCurrentPreference().createFolder(named: name, in: self.session.remotePath, profile: profile, session: self.session)
                    await self.refreshRemote()
                }
            } catch {
                self.recordError(error, category: "file.create-folder")
                self.session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func renameItem(_ item: FileItem, to newName: String) {
        Task {
            do {
                switch item.source {
                case .local:
                    try await self.localFileSystem.renameItem(at: item.path, to: newName)
                    await self.refreshLocal()
                case .remote:
                    guard let profile = activeProfile else { return }
                    try await self.remoteClientForCurrentPreference().renameItem(at: item.path, to: newName, profile: profile, session: self.session)
                    await self.refreshRemote()
                }
            } catch {
                self.recordError(error, category: "file.rename")
                self.session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteItem(_ item: FileItem) {
        Task {
            do {
                switch item.source {
                case .local:
                    try await self.localFileSystem.deleteItem(at: item.path)
                    self.selectedLocalFile = nil
                    self.selectedLocalFileIDs.remove(item.id)
                    self.selectedLocalFiles.removeAll { $0.id == item.id }
                    await self.refreshLocal()
                case .remote:
                    guard let profile = activeProfile else { return }
                    try await self.remoteClientForCurrentPreference().deleteItem(at: item.path, profile: profile, session: self.session)
                    self.selectedRemoteFile = nil
                    self.selectedRemoteFileIDs.remove(item.id)
                    self.selectedRemoteFiles.removeAll { $0.id == item.id }
                    await self.refreshRemote()
                }
            } catch {
                self.recordError(error, category: "file.delete")
                self.session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func uploadSelectedItem() {
        self.uploadItems(self.selectedLocalFiles)
    }

    func uploadItem(_ item: FileItem) {
        self.uploadItems([item])
    }

    func uploadItems(_ items: [FileItem], conflictPolicy: TransferConflictPolicy = .ask) {
        for item in items {
            self.uploadItemImmediately(item, conflictPolicy: conflictPolicy)
        }
    }

    private func uploadItemImmediately(_ item: FileItem, conflictPolicy: TransferConflictPolicy = .ask) {
        guard item.source == .local,
              let profile = activeProfile,
              session.state == .connected
        else { return }
        self.activePane = .local
        self.selectedLocalFile = item
        self.selectedLocalFiles = [item]
        self.selectedLocalFileIDs = [item.id]
        let destination = self.remotePathAppending(self.session.remotePath, item.name)
        let job = TransferJob(
            direction: .upload,
            sourcePath: item.path,
            destinationPath: destination,
            byteCount: item.size,
            isFolder: item.kind == .folder,
            serverName: profile.displayName,
            profileID: profile.id,
            protocolKind: profile.protocolKind,
            backendKind: self.preferences.remoteBackendKind
        )
        if self.remoteItems.contains(where: { $0.path == destination }) {
            switch conflictPolicy {
            case .ask:
                if self.preferences.confirmBeforeOverwrite {
                    self.queueTransferConflict(TransferConflict(job: job, profile: profile, existingPath: destination))
                    return
                }
            case .replace:
                break
            case .skip:
                return
            }
        }
        self.enqueueTransfer(job, profile: profile)
    }

    func openTerminalSession() {
        guard let profile = activeProfile else { return }
        Task {
            do {
                let command = try TerminalCommandFactory.sshCommand(for: profile)
                try await self.terminalLauncher.launch(command)
            } catch {
                self.session.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func downloadSelectedItem() {
        self.downloadItems(self.selectedRemoteFiles)
    }

    func downloadItem(_ item: FileItem) {
        self.downloadItems([item])
    }

    func downloadItems(_ items: [FileItem], conflictPolicy: TransferConflictPolicy = .ask) {
        for item in items {
            self.downloadItemImmediately(item, conflictPolicy: conflictPolicy)
        }
    }

    private func downloadItemImmediately(_ item: FileItem, conflictPolicy: TransferConflictPolicy = .ask) {
        guard item.source == .remote,
              let profile = activeProfile,
              session.state == .connected
        else { return }
        self.activePane = .remote
        self.selectedRemoteFile = item
        self.selectedRemoteFiles = [item]
        self.selectedRemoteFileIDs = [item.id]
        let destination = URL(fileURLWithPath: session.localPath).appendingPathComponent(item.name).path
        let job = TransferJob(
            direction: .download,
            sourcePath: item.path,
            destinationPath: destination,
            byteCount: item.size,
            isFolder: item.kind == .folder,
            serverName: profile.displayName,
            profileID: profile.id,
            protocolKind: profile.protocolKind,
            backendKind: self.preferences.remoteBackendKind
        )
        if FileManager.default.fileExists(atPath: destination) {
            switch conflictPolicy {
            case .ask:
                if self.preferences.confirmBeforeOverwrite {
                    self.queueTransferConflict(TransferConflict(job: job, profile: profile, existingPath: destination))
                    return
                }
            case .replace:
                break
            case .skip:
                return
            }
        }
        self.enqueueTransfer(job, profile: profile)
    }

    func transferDraggedItems(ids: [String], to destination: FileSource) -> Bool {
        switch destination {
        case .local:
            let items = self.items(matching: Set(ids), in: self.remoteItems)
            guard !items.isEmpty else { return false }
            self.downloadItems(items)
            return true
        case .remote:
            let items = self.items(matching: Set(ids), in: self.localItems)
            guard !items.isEmpty else { return false }
            self.uploadItems(items)
            return true
        }
    }

    func transferDroppedItems(_ items: [FileItem], to destination: FileSource) -> Bool {
        switch destination {
        case .local:
            let remoteItems = items.filter { $0.source == .remote }
            guard !remoteItems.isEmpty else { return false }
            self.downloadItems(remoteItems)
            return true
        case .remote:
            let localItems = items.filter { $0.source == .local }
            guard !localItems.isEmpty else { return false }
            self.uploadItems(localItems)
            return true
        }
    }

    private func enqueueTransfer(_ job: TransferJob, profile: ServerProfile) {
        var queued = job
        queued.status = .queued
        queued.profileID = queued.profileID ?? profile.id
        queued.protocolKind = queued.protocolKind ?? profile.protocolKind
        queued.serverName = queued.serverName ?? profile.displayName
        queued.backendKind = queued.backendKind ?? self.preferences.remoteBackendKind
        self.transferProfiles[queued.id] = profile
        self.replaceTransferJob(queued)
        self.processTransferQueue()
    }

    private func processTransferQueue() {
        let runningCount = self.transferJobs.filter(\.isRunning).count
        let capacity = max(preferences.transferConcurrency - runningCount, 0)
        guard capacity > 0 else { return }

        let queuedJobs = self.transferJobs.filter(\.isQueued).prefix(capacity)
        for job in queuedJobs {
            guard let profile = self.profile(for: job) else { continue }
            var starting = job
            starting.status = .running(progress: 0, bytesPerSecond: nil)
            starting.startedAt = Date()
            self.replaceTransferJob(starting)
            Task {
                await self.runTransfer(starting, profile: profile)
            }
        }
    }

    private func runTransfer(_ job: TransferJob, profile: ServerProfile) async {
        do {
            let updateModel = self
            let client = self.transferClient(for: job.backendKind)
            try await client.enqueue(job, profile: profile) { [updateModel] updated in
                await MainActor.run {
                    updateModel.replaceTransferJob(updated)
                }
            }
            if let completed = transferJobs.first(where: { $0.id == job.id }) {
                try? await self.transferHistoryRepository.append(completed)
                self.notifyTransferCompleted(completed)
            }
            self.transferProfiles[job.id] = nil
            await self.refreshLocal()
            await self.refreshRemote()
        } catch is CancellationError {
            var cancelled = self.transferJobs.first(where: { $0.id == job.id }) ?? job
            cancelled.status = .cancelled
            cancelled.finishedAt = Date()
            self.replaceTransferJob(cancelled)
            self.transferProfiles[job.id] = nil
            try? await self.transferHistoryRepository.append(cancelled)
        } catch {
            self.recordError(error, category: "transfer.run")
            var failed = job
            failed.status = .failed(message: error.localizedDescription)
            failed.finishedAt = Date()
            self.replaceTransferJob(failed)
            self.transferProfiles[job.id] = nil
            try? await self.transferHistoryRepository.append(failed)
            self.notifyTransferFailed(failed)
        }
        self.processTransferQueue()
    }

    private func notifyTransferCompleted(_ job: TransferJob) {
        guard case .succeeded = job.status else { return }
        let displayPath = job.direction == .download ? job.destinationPath : job.sourcePath
        let fileName = URL(fileURLWithPath: displayPath).lastPathComponent
        let itemKind = job.isFolder ? self.loc("fileKind.folder") : self.loc("fileKind.file")
        let action = job.direction == .download ? self.loc("transfer.downloaded") : self.loc("transfer.uploaded")
        let serverName = job.serverName ?? self.loc("common.server")
        self.notifyInBackground(
            title: self.loc("notification.transferCompletedTitle", action, itemKind),
            body: self.loc("notification.transferCompletedBody", fileName, serverName),
            identifier: "transfer-completed-\(job.id.rawValue.uuidString)"
        )
    }

    private func notifyTransferFailed(_ job: TransferJob) {
        let displayPath = job.direction == .download ? job.destinationPath : job.sourcePath
        let fileName = URL(fileURLWithPath: displayPath).lastPathComponent
        let action = job.direction.localizedTitle
        let serverName = job.serverName ?? self.loc("common.server")
        self.notifyInBackground(
            title: self.loc("notification.transferFailedTitle", action),
            body: self.loc("notification.transferFailedBody", fileName, serverName),
            identifier: "transfer-failed-\(job.id.rawValue.uuidString)"
        )
    }

    func skipPendingConflict() {
        if self.conflictApplyToRemaining {
            self.queuedTransferConflicts.removeAll()
        }
        self.pendingTransferConflict = nil
        self.showNextTransferConflict()
    }

    func overwritePendingConflict() {
        guard let conflict = pendingTransferConflict else { return }
        let remaining = self.conflictApplyToRemaining ? self.queuedTransferConflicts : []
        self.pendingTransferConflict = nil
        self.enqueueTransfer(conflict.job, profile: conflict.profile)
        for conflict in remaining {
            self.enqueueTransfer(conflict.job, profile: conflict.profile)
        }
        if self.conflictApplyToRemaining {
            self.queuedTransferConflicts.removeAll()
        }
        self.showNextTransferConflict()
    }

    func renameAndRunPendingConflict() {
        guard let conflict = pendingTransferConflict else { return }
        let name = self.conflictRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var renamed = conflict.job
        renamed.destinationPath = self.renamedDestinationPath(for: renamed, name: name)
        self.pendingTransferConflict = nil
        self.enqueueTransfer(renamed, profile: conflict.profile)
        self.showNextTransferConflict()
    }

    private func queueTransferConflict(_ conflict: TransferConflict) {
        if self.pendingTransferConflict == nil {
            self.pendingTransferConflict = conflict
            self.conflictRenameText = self.suggestedConflictName(for: conflict)
            self.conflictApplyToRemaining = false
        } else {
            self.queuedTransferConflicts.append(conflict)
        }
    }

    private func showNextTransferConflict() {
        self.conflictApplyToRemaining = false
        if self.queuedTransferConflicts.isEmpty {
            self.conflictRenameText = ""
            return
        }
        let next = self.queuedTransferConflicts.removeFirst()
        self.pendingTransferConflict = next
        self.conflictRenameText = self.suggestedConflictName(for: next)
    }

    private func suggestedConflictName(for conflict: TransferConflict) -> String {
        let original = URL(fileURLWithPath: conflict.job.destinationPath).lastPathComponent
        let existingNames: Set<String>
        switch conflict.job.direction {
        case .upload:
            existingNames = Set(self.remoteItems.map(\.name))
        case .download:
            let parent = URL(fileURLWithPath: conflict.job.destinationPath).deletingLastPathComponent()
            existingNames = self.localNames(in: parent)
        }
        return self.suggestedConflictName(for: original, avoiding: existingNames)
    }

    private func suggestedConflictName(for original: String, avoiding existingNames: Set<String>) -> String {
        let url = URL(fileURLWithPath: original)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let first = ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)"
        guard existingNames.contains(first) else { return first }
        for index in 2 ... 999 {
            let candidate = ext.isEmpty ? "\(base) copy \(index)" : "\(base) copy \(index).\(ext)"
            if !existingNames.contains(candidate) {
                return candidate
            }
        }
        return ext.isEmpty ? "\(base) copy \(UUID().uuidString)" : "\(base) copy \(UUID().uuidString).\(ext)"
    }

    private func localNames(in directory: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    private func renamedDestinationPath(for job: TransferJob, name: String) -> String {
        switch job.direction {
        case .upload:
            self.remotePathAppending(self.remoteParentPath(of: job.destinationPath), name)
        case .download:
            URL(fileURLWithPath: job.destinationPath).deletingLastPathComponent().appendingPathComponent(name).path
        }
    }

    private func remoteParentPath(of path: String) -> String {
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        guard let slash = trimmed.lastIndex(of: "/") else { return "/" }
        if slash == trimmed.startIndex { return "/" }
        return String(trimmed[..<slash])
    }

    private func remotePathAppending(_ base: String, _ name: String) -> String {
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return trimmed.isEmpty ? "/\(name)" : "\(trimmed)/\(name)"
    }

    private func replaceTransferJob(_ job: TransferJob) {
        if let index = transferJobs.firstIndex(where: { $0.id == job.id }) {
            self.transferJobs[index] = job
        } else {
            self.transferJobs.insert(job, at: 0)
        }
    }

    private func saveActiveTabSnapshot() {
        guard let selectedTabID, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        self.tabs[index].session = self.session
        self.tabs[index].localItems = self.localItems
        self.tabs[index].remoteItems = self.remoteItems
        self.tabs[index].selectedLocalFile = self.selectedLocalFile
        self.tabs[index].selectedRemoteFile = self.selectedRemoteFile
        self.tabs[index].selectedLocalFileIDs = self.selectedLocalFileIDs
        self.tabs[index].selectedRemoteFileIDs = self.selectedRemoteFileIDs
        self.tabs[index].selectedLocalFiles = self.selectedLocalFiles
        self.tabs[index].selectedRemoteFiles = self.selectedRemoteFiles
        self.tabs[index].activePane = self.activePane
        if let profile = selectedProfile {
            self.tabs[index].title = profile.displayName
        } else if self.session.remotePath != "/" {
            self.tabs[index].title = self.session.remotePath
        } else {
            self.tabs[index].title = self.loc("tab.newConnection")
        }
    }

    func selectTab(_ tabID: WorkspaceTab.ID) {
        self.saveActiveTabSnapshot()
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        self.selectedTabID = tabID
        self.session = tab.session
        self.localItems = tab.localItems
        self.remoteItems = tab.remoteItems
        self.selectedLocalFile = tab.selectedLocalFile
        self.selectedRemoteFile = tab.selectedRemoteFile
        self.selectedLocalFileIDs = tab.selectedLocalFileIDs
        self.selectedRemoteFileIDs = tab.selectedRemoteFileIDs
        self.selectedLocalFiles = tab.selectedLocalFiles
        self.selectedRemoteFiles = tab.selectedRemoteFiles
        self.activePane = tab.activePane
    }

    func clearCompletedTransfers() {
        self.transferJobs.removeAll { job in
            if case .succeeded = job.status { return true }
            return false
        }
        Task {
            try? await self.transferHistoryRepository.clear { job in
                if case .succeeded = job.status { return true }
                return false
            }
        }
    }

    func clearFailedTransfers() {
        self.transferJobs.removeAll { job in
            if case .failed = job.status { return true }
            return false
        }
        Task {
            try? await self.transferHistoryRepository.clear { job in
                if case .failed = job.status { return true }
                return false
            }
        }
    }

    func retryFailedTransfers() {
        let failedJobs = self.transferJobs.filter { job in
            if case .failed = job.status { return true }
            return false
        }
        for var job in failedJobs {
            guard let profile = self.profile(for: job) else { continue }
            job.status = .queued
            job.startedAt = nil
            job.finishedAt = nil
            self.enqueueTransfer(job, profile: profile)
        }
    }

    func cancelActiveTransfers() {
        let activeIDs = self.transferJobs.compactMap { job -> TransferJobID? in
            if case .running = job.status { return job.id }
            return nil
        }
        self.transferJobs = self.transferJobs.map { job in
            guard case .running = job.status else { return job }
            var cancelled = job
            cancelled.status = .cancelled
            cancelled.finishedAt = Date()
            return cancelled
        }
        Task {
            for id in activeIDs {
                let backendKind = self.transferJobs.first { $0.id == id }?.backendKind
                try? await self.transferClient(for: backendKind).cancel(id: id)
            }
        }
        self.processTransferQueue()
    }

    func cancelTransfer(id: TransferJobID) {
        guard let index = transferJobs.firstIndex(where: { $0.id == id }) else { return }
        switch self.transferJobs[index].status {
        case .queued:
            self.transferJobs[index].status = .cancelled
            self.transferJobs[index].finishedAt = Date()
            self.transferProfiles[id] = nil
            self.processTransferQueue()
        case .running:
            let backendKind = self.transferJobs[index].backendKind
            self.transferJobs[index].status = .cancelled
            self.transferJobs[index].finishedAt = Date()
            self.transferProfiles[id] = nil
            Task {
                try? await self.transferClient(for: backendKind).cancel(id: id)
                await MainActor.run {
                    self.processTransferQueue()
                }
            }
        case .succeeded, .failed, .cancelled:
            break
        }
    }

    func newTab() {
        self.saveActiveTabSnapshot()
        let tab = WorkspaceTab()
        self.tabs.append(tab)
        self.selectTab(tab.id)
        Task { await self.refreshLocal() }
    }

    func closeSelectedTab() {
        guard let selectedTabID else { return }
        self.requestCloseTab(selectedTabID)
    }

    func requestCloseTab(_ tabID: WorkspaceTab.ID) {
        guard self.tabs.count > 1 else { return }
        guard let tab = self.tabs.first(where: { $0.id == tabID }) else { return }
        switch tab.session.state {
        case .disconnected, .failed:
            self.forceCloseTab(tabID)
        default:
            self.pendingCloseTabID = tabID
        }
    }

    func confirmCloseTab() {
        guard let tabID = self.pendingCloseTabID else { return }
        self.pendingCloseTabID = nil
        if let index = self.tabs.firstIndex(where: { $0.id == tabID }) {
            self.disconnectTabSession(self.tabs[index].session)
            self.tabs[index].session.state = .disconnected
        }
        self.forceCloseTab(tabID)
    }

    func cancelCloseTab() {
        self.pendingCloseTabID = nil
    }

    private func forceCloseTab(_ tabID: WorkspaceTab.ID) {
        guard self.tabs.count > 1 else { return }
        let wasSelected = self.selectedTabID == tabID
        self.tabs.removeAll { $0.id == tabID }
        if wasSelected, let first = tabs.first {
            self.selectTab(first.id)
        }
    }

    private func disconnectTabSession(_ session: ConnectionSession) {
        Task {
            try? await self.remoteClientForCurrentPreference().disconnect(session: session)
        }
    }

    var activeProfile: ServerProfile? {
        if let selectedProfile {
            return selectedProfile
        }
        if let serverID = session.serverID {
            return self.profiles.first { $0.id == serverID }
        }
        return nil
    }

    private func remoteClientForCurrentPreference() -> RemoteFileSystemClient {
        switch self.preferences.remoteBackendKind {
        case .systemSSH:
            self.remoteFileSystem
        case .nativeSwiftExperimental:
            self.nativeRemoteFileSystem
        }
    }

    private func transferClientForCurrentPreference() -> TransferClient {
        self.transferClient(for: self.preferences.remoteBackendKind)
    }

    private func transferClient(for backendKind: RemoteBackendKind?) -> TransferClient {
        switch backendKind ?? self.preferences.remoteBackendKind {
        case .systemSSH:
            self.transferClient
        case .nativeSwiftExperimental:
            self.nativeTransferClient
        }
    }

    private func profile(for job: TransferJob) -> ServerProfile? {
        if let profile = self.transferProfiles[job.id] {
            return profile
        }
        if let profileID = job.profileID {
            return self.profiles.first { $0.id == profileID }
        }
        return self.activeProfile
    }

    private func selectedFile(in source: FileSource) -> FileItem? {
        switch source {
        case .local:
            self.selectedLocalFile
        case .remote:
            self.selectedRemoteFile
        }
    }

    private func items(matching ids: Set<String>, in items: [FileItem]) -> [FileItem] {
        items.filter { ids.contains($0.id) }
    }

    private func loc(_ key: String, _ args: CVarArg...) -> String {
        let format = LocalizationManager.shared.localized(key)
        if args.isEmpty { return format }
        return String(format: format, arguments: args)
    }
}

@MainActor
enum AppIconController {
    static func apply(_ variant: AppIconVariant) {
        guard let image = NSImage(contentsOfFile: self.iconPath(for: variant)) else {
            NSApplication.shared.applicationIconImage = nil
            return
        }
        NSApplication.shared.applicationIconImage = image
    }

    private static func iconPath(for variant: AppIconVariant) -> String {
        let iconName = switch variant {
        case .light:
            "Driftline"
        case .dark:
            "DriftlineDark"
        }

        if let bundledPath = Bundle.main.path(forResource: iconName, ofType: "icns") {
            return bundledPath
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets")
            .appendingPathComponent("\(iconName).icns")
            .path
    }
}

@MainActor
enum AppThemeController {
    static func apply(_ variant: AppThemeVariant) {
        let appearance: NSAppearance? = switch variant {
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        case .system:
            nil
        }

        NSApplication.shared.appearance = appearance
        for window in NSApplication.shared.windows {
            window.appearance = appearance
            window.contentView?.appearance = appearance
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

enum TransferConflictPolicy {
    case ask
    case replace
    case skip
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
        switch self.kind {
        case .createFolder:
            String(format: LocalizationManager.shared.localized("file.newSourceFolder"), self.source.localizedTitle)
        case .rename:
            LocalizationManager.shared.localized("file.renameItem")
        }
    }
}

struct PendingHostTrust: Identifiable, Equatable {
    var id: String {
        "\(self.host):\(self.port):\(self.algorithm):\(self.fingerprint)"
    }

    var host: String
    var port: Int
    var algorithm: String
    var fingerprint: String
    var knownHostsLine: String
}

struct ServerProfileDraft: Identifiable, Equatable {
    enum AuthKind: String, CaseIterable, Identifiable {
        case agent
        case password
        case privateKey
        case none

        var id: String {
            rawValue
        }

        var localizedTitle: String {
            switch self {
            case .agent:
                LocalizationManager.shared.localized("profile.auth.agent")
            case .password:
                LocalizationManager.shared.localized("profile.auth.password")
            case .privateKey:
                LocalizationManager.shared.localized("profile.auth.privateKey")
            case .none:
                LocalizationManager.shared.localized("profile.auth.none")
            }
        }
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
        case let .privateKey(path, passphraseReference):
            self.authKind = .privateKey
            self.privateKeyPath = path
            self.password = ""
            self.passphrase = ""
            self.storePassphrase = passphraseReference != nil
        case .none:
            self.authKind = .none
            self.privateKeyPath = "~/.ssh/id_ed25519"
            self.password = ""
            self.passphrase = ""
            self.storePassphrase = false
        }
    }

    func makeProfile() -> ServerProfile {
        let trimmedHost = self.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = self.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let credentialAccount = "\(trimmedUsername)@\(trimmedHost)"
        let authenticationMethod: AuthenticationMethod
        switch self.authKind {
        case .agent:
            authenticationMethod = .agent
        case .password:
            authenticationMethod = .password(CredentialReference(service: "app.driftline.credentials", account: credentialAccount))
        case .privateKey:
            let passphraseReference = self.storePassphrase
                ? CredentialReference(service: "app.driftline.private-key-passphrase", account: credentialAccount)
                : nil
            authenticationMethod = .privateKey(path: self.privateKeyPath, passphrase: passphraseReference)
        case .none:
            authenticationMethod = .none
        }

        return ServerProfile(
            id: self.id,
            displayName: self.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            host: trimmedHost,
            port: self.port,
            protocolKind: self.protocolKind,
            username: trimmedUsername,
            authenticationMethod: authenticationMethod,
            remoteDefaultPath: self.remoteDefaultPath.isEmpty ? "/" : self.remoteDefaultPath,
            localDefaultPath: self.localDefaultPath.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : self.localDefaultPath,
            notes: self.notes,
            tags: self.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            isFavorite: self.isFavorite,
            groupName: self.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self.groupName.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }
}

struct WorkspaceTab: Identifiable {
    var id = UUID()
    var title = LocalizationManager.shared.localized("tab.newConnection")
    var session = ConnectionSession(state: .disconnected, protocolKind: .sftp)
    var localItems: [FileItem] = []
    var remoteItems: [FileItem] = []
    var selectedLocalFile: FileItem?
    var selectedRemoteFile: FileItem?
    var selectedLocalFileIDs: Set<String> = []
    var selectedRemoteFileIDs: Set<String> = []
    var selectedLocalFiles: [FileItem] = []
    var selectedRemoteFiles: [FileItem] = []
    var activePane: FileSource = .local
}

struct ToastMessage {
    var text: String
    var systemImage = "checkmark.circle.fill"
    var iconColor: Color = .green
}

struct UserAlert {
    var title: String
    var message: String
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
