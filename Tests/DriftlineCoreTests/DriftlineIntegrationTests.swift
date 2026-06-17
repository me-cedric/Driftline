@testable import DriftlineApp
@testable import DriftlineCore
import XCTest

final class DriftlineIntegrationTests: XCTestCase {
    func testValidConnectURLParses() throws {
        let request = try self.connectRequest("driftline://connect?protocol=sftp&host=example.com&port=22&username=user&path=%2Fvar%2Fwww")

        XCTAssertEqual(request.protocolKind, .sftp)
        XCTAssertEqual(request.host, "example.com")
        XCTAssertEqual(request.port, 22)
        XCTAssertEqual(request.username, "user")
        XCTAssertEqual(request.path, "/var/www")
    }

    func testInvalidProtocolRejected() throws {
        XCTAssertThrowsError(try DriftlineDeepLink.parse(XCTUnwrap(URL(string: "driftline://connect?protocol=ftp&host=example.com&port=21&username=user")))) { error in
            XCTAssertEqual(error as? DriftlineDeepLinkError, .invalidProtocol("ftp"))
        }
    }

    func testInvalidPortRejected() throws {
        XCTAssertThrowsError(try DriftlineDeepLink.parse(XCTUnwrap(URL(string: "driftline://connect?protocol=sftp&host=example.com&port=70000&username=user")))) { error in
            XCTAssertEqual(error as? DriftlineDeepLinkError, .invalidPort("70000"))
        }
    }

    func testMissingHostRejected() throws {
        XCTAssertThrowsError(try DriftlineDeepLink.parse(XCTUnwrap(URL(string: "driftline://connect?protocol=sftp&port=22&username=user")))) { error in
            XCTAssertEqual(error as? DriftlineDeepLinkError, .missingHost)
        }
    }

    func testSecretLikeQueryParamsIgnored() throws {
        let request = try self.connectRequest("driftline://connect?protocol=sftp&host=example.com&port=22&username=user&password=nope&token=nope&privateKey=nope")

        XCTAssertEqual(request.ignoredSecretParameters, ["password", "privateKey", "token"])
        XCTAssertEqual(request.host, "example.com")
    }

    func testPathDecodingWorks() throws {
        let request = try self.connectRequest("driftline://connect?protocol=sftp&host=example.com&port=22&username=user&path=%2Fspace%20folder")

        XCTAssertEqual(request.path, "/space folder")
    }

    func testOpenURLParses() throws {
        let action = try DriftlineDeepLink.parse(XCTUnwrap(URL(string: "driftline://open")))

        guard case .open = action else {
            XCTFail("Expected open action")
            return
        }
    }

    func testStatusSnapshotUsesTransferStats() {
        let stats = TransferStats(activeTransfers: 2, queuedTransfers: 1)
        let snapshot = DriftlineIntegrationStatusSnapshot.fromTransferStats(stats, lastUpdatedAt: Date(timeIntervalSince1970: 42))

        XCTAssertEqual(snapshot.activeTransferCount, 2)
        XCTAssertEqual(snapshot.queuedTransferCount, 1)
        XCTAssertEqual(snapshot.failedTransferCount, 0)
        XCTAssertEqual(snapshot.currentState, .transferring)
        XCTAssertEqual(snapshot.lastUpdatedAt, Date(timeIntervalSince1970: 42))
    }

    func testStatusSnapshotUsesVisibleSessionFailureAsError() {
        let stats = TransferStats()
        let snapshot = DriftlineIntegrationStatusSnapshot.fromTransferStats(stats, sessionState: .failed(message: "Connection failed"), lastUpdatedAt: Date(timeIntervalSince1970: 42))

        XCTAssertEqual(snapshot.currentState, .error)
        XCTAssertEqual(snapshot.activeTransferCount, 0)
        XCTAssertEqual(snapshot.queuedTransferCount, 0)
        XCTAssertEqual(snapshot.failedTransferCount, 0)
    }

    func testSanitizedStateSortsRecentsAndIncludesFavorites() {
        let favorite = ServerProfile(
            displayName: "Favorite",
            host: "files.example.com",
            port: 2222,
            protocolKind: .sftp,
            username: "demo",
            authenticationMethod: .agent,
            isFavorite: true
        )
        let older = RecentServer(
            profileID: ServerProfileID(),
            displayName: "Older",
            host: "old.example.com",
            protocolKind: .sftp,
            localPath: "/tmp",
            remotePath: "/old",
            connectedAt: Date(timeIntervalSince1970: 10)
        )
        let newer = RecentServer(
            profileID: favorite.id,
            displayName: "Newer",
            host: favorite.host,
            protocolKind: .sftp,
            localPath: "/tmp",
            remotePath: "/new",
            connectedAt: Date(timeIntervalSince1970: 20)
        )

        let state = DriftlineIntegrationState.sanitized(
            profiles: [favorite],
            recents: [older, newer],
            transferStats: TransferStats(),
            lastUpdatedAt: Date(timeIntervalSince1970: 30)
        )

        XCTAssertEqual(state.recents.map(\.displayName), ["Newer", "Older"])
        XCTAssertEqual(state.favorites.map(\.displayName), ["Favorite"])
        XCTAssertEqual(state.favorites.first?.port, 2222)
        XCTAssertEqual(state.favorites.first?.username, "demo")
        XCTAssertEqual(state.favorites.first?.path, "/new")
    }

    func testSanitizedStateExcludesAuthMetadata() throws {
        let profile = ServerProfile(
            displayName: "Secure",
            host: "example.com",
            protocolKind: .sftp,
            username: "demo",
            authenticationMethod: .agent,
            isFavorite: true
        )

        let state = DriftlineIntegrationState.sanitized(
            profiles: [profile],
            recents: [],
            transferStats: TransferStats()
        )
        let data = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("example.com"))
        XCTAssertFalse(json.contains("authenticationMethod"))
        XCTAssertFalse(json.contains("CredentialReference"))
        XCTAssertFalse(json.contains("agent"))
    }

    func testIntegrationSnapshotStoreRoundTripsState() async throws {
        let url = self.temporaryFileURL("integration-snapshot.json")
        let store = JSONDriftlineIntegrationStateStore(url: url)
        let state = DriftlineIntegrationState(
            recents: [
                DriftlineIntegrationConnectionSummary(
                    id: "recent",
                    displayName: "Recent",
                    protocolKind: .sftp,
                    host: "files.example.com",
                    port: 22,
                    username: "demo",
                    path: "/incoming",
                    lastUsedAt: Date(timeIntervalSince1970: 10),
                    isFavorite: false
                ),
            ],
            favorites: [],
            status: DriftlineIntegrationStatusSnapshot(
                activeTransferCount: 1,
                queuedTransferCount: 2,
                failedTransferCount: 0,
                currentState: .transferring,
                lastUpdatedAt: Date(timeIntervalSince1970: 20)
            )
        )

        try await store.save(state)
        let loaded = try await store.load()

        XCTAssertEqual(loaded, state)
    }

    func testWidgetSnapshotProviderFallsBackToIdleState() async {
        let snapshot = await DriftlineWidgetSnapshotProvider(store: nil).snapshot()

        XCTAssertTrue(snapshot.recents.isEmpty)
        XCTAssertTrue(snapshot.favorites.isEmpty)
        XCTAssertEqual(snapshot.status.currentState, .idle)
        XCTAssertEqual(snapshot.status.activeTransferCount, 0)
    }

    func testWidgetSnapshotProviderLoadsStoredState() async throws {
        let store = JSONDriftlineIntegrationStateStore(url: self.temporaryFileURL("provider-snapshot.json"))
        let expected = DriftlineIntegrationState(
            status: DriftlineIntegrationStatusSnapshot(
                activeTransferCount: 1,
                queuedTransferCount: 0,
                failedTransferCount: 0,
                currentState: .transferring
            )
        )
        try await store.save(expected)

        let snapshot = await DriftlineWidgetSnapshotProvider(store: store).snapshot()

        XCTAssertEqual(snapshot.status.currentState, .transferring)
        XCTAssertEqual(snapshot.status.activeTransferCount, 1)
    }

    func testAppGroupIdentifierComesFromEnvironment() {
        let identifier = DriftlineAppGroupConfiguration.identifier(environment: [
            DriftlineAppGroupConfiguration.identifierKey: " group.app.driftline.Driftline ",
        ])

        XCTAssertEqual(identifier, "group.app.driftline.Driftline")
    }

    func testAppGroupIdentifierSkipsEmptyOrUnexpandedValues() {
        XCTAssertNil(DriftlineAppGroupConfiguration.identifier(environment: [
            DriftlineAppGroupConfiguration.identifierKey: "  ",
        ]))
        XCTAssertNil(DriftlineAppGroupConfiguration.identifier(environment: [
            DriftlineAppGroupConfiguration.identifierKey: "$(DRIFTLINE_APP_GROUP_IDENTIFIER)",
        ]))
    }

    func testWidgetConnectURLUsesSanitizedFields() throws {
        let summary = DriftlineIntegrationConnectionSummary(
            id: "favorite",
            displayName: "Files",
            protocolKind: .sftp,
            host: "files.example.com",
            port: 2222,
            username: "demo",
            path: "/incoming",
            lastUsedAt: Date(),
            isFavorite: true
        )

        let url = try XCTUnwrap(DriftlineWidgetActionURLBuilder.connectURL(for: summary))
        let request = try self.connectRequest(url.absoluteString)
        let queryNames = Set(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? [])

        XCTAssertEqual(request.host, "files.example.com")
        XCTAssertEqual(request.port, 2222)
        XCTAssertEqual(request.username, "demo")
        XCTAssertEqual(request.path, "/incoming")
        XCTAssertEqual(queryNames, ["protocol", "host", "port", "username", "path"])
    }

    func testWidgetConnectionActionsSkipInvalidSummaries() {
        let state = DriftlineIntegrationState(
            recents: [
                DriftlineIntegrationConnectionSummary(
                    id: "missing-user",
                    displayName: "Missing User",
                    protocolKind: .sftp,
                    host: "example.com",
                    port: 22
                ),
                DriftlineIntegrationConnectionSummary(
                    id: "valid",
                    displayName: "Valid",
                    protocolKind: .sftp,
                    host: "files.example.com",
                    port: 22,
                    username: "demo"
                ),
            ]
        )

        let actions = DriftlineWidgetActionURLBuilder.connectionActions(from: state, limit: 4)

        XCTAssertEqual(actions.map(\.id), ["valid"])
    }

    func testInvalidSnapshotSummariesAreSkipped() {
        let state = DriftlineIntegrationState(
            recents: [
                DriftlineIntegrationConnectionSummary(
                    id: "invalid",
                    displayName: "Invalid",
                    protocolKind: .sftp,
                    host: "",
                    port: 22,
                    username: "demo"
                ),
                DriftlineIntegrationConnectionSummary(
                    id: "valid",
                    displayName: "Valid",
                    protocolKind: .sftp,
                    host: "example.com",
                    port: 22,
                    username: "demo"
                ),
            ]
        )

        XCTAssertEqual(state.recents.map(\.id), ["valid"])
    }

    func testEncodedWidgetSnapshotContainsOnlySanitizedConnectionFields() throws {
        let state = DriftlineIntegrationState(
            recents: [
                DriftlineIntegrationConnectionSummary(
                    id: "recent",
                    displayName: "Recent",
                    protocolKind: .sftp,
                    host: "example.com",
                    port: 22,
                    username: "demo",
                    path: "/"
                ),
            ]
        )
        let data = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("example.com"))
        XCTAssertFalse(json.contains("sensitive-value"))
    }

    @MainActor
    func testDeepLinkPrefillsQuickConnectDraft() async throws {
        let model = AppModel(
            profileRepository: InMemoryServerProfileRepository(),
            preferencesRepository: InMemoryViewPreferencesRepository(),
            transferHistoryRepository: InMemoryTransferHistoryRepository(),
            bookmarkRepository: InMemoryServerBookmarkRepository(),
            recentRepository: InMemoryRecentServerRepository(),
            localFileSystem: EmptyLocalFileSystemClient(),
            notificationController: NoopNotificationController()
        )
        try await Task.sleep(nanoseconds: 10_000_000)

        try model.handleDeepLink(XCTUnwrap(URL(string: "driftline://connect?protocol=sftp&host=example.com&port=2222&username=deploy&path=%2Fsrv")))

        let draft = try XCTUnwrap(model.profileDraft)
        XCTAssertEqual(model.selectedSidebarItem, SidebarItem.quickConnect.id)
        XCTAssertFalse(model.connectAfterSavingDraft)
        XCTAssertEqual(draft.protocolKind, .sftp)
        XCTAssertEqual(draft.host, "example.com")
        XCTAssertEqual(draft.port, 2222)
        XCTAssertEqual(draft.username, "deploy")
        XCTAssertEqual(draft.remoteDefaultPath, "/srv")
    }

    private func connectRequest(_ string: String) throws -> DriftlineConnectRequest {
        let action = try DriftlineDeepLink.parse(URL(string: string)!)
        guard case let .connect(request) = action else {
            XCTFail("Expected connect action")
            throw DriftlineDeepLinkError.unsupportedAction
        }
        return request
    }

    private func temporaryFileURL(_ filename: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftlineIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        return directory.appendingPathComponent(filename)
    }
}

private final class EmptyLocalFileSystemClient: LocalFileSystemClient, @unchecked Sendable {
    func listDirectory(at _: String, preferences _: FileListPreferences) async throws -> [FileItem] {
        []
    }

    func createFolder(named _: String, in _: String) async throws {}

    func renameItem(at _: String, to _: String) async throws {}

    func deleteItem(at _: String) async throws {}

    func itemExists(at _: String) async -> Bool {
        false
    }
}

private final class NoopNotificationController: AppNotificationControlling {
    func requestPermissionIfNeeded() async {}

    func notifyIfBackground(isEnabled _: Bool, title _: String, body _: String, identifier _: String) {}
}
