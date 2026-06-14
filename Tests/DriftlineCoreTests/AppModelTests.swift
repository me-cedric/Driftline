@testable import DriftlineApp
@testable import DriftlineCore
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    func testNewTabPopulatesLocalItems() async throws {
        let expectedItems = [
            FileItem(name: "Documents", path: "/tmp/test/Documents", kind: .folder, source: .local),
            FileItem(name: "file.txt", path: "/tmp/test/file.txt", kind: .file, source: .local),
        ]

        let mockFS = MockLocalFileSystemClient { _, _ in
            expectedItems
        }

        let model = AppModel(
            profileRepository: InMemoryServerProfileRepository(),
            preferencesRepository: InMemoryViewPreferencesRepository(),
            transferHistoryRepository: InMemoryTransferHistoryRepository(),
            bookmarkRepository: InMemoryServerBookmarkRepository(),
            recentRepository: InMemoryRecentServerRepository(),
            localFileSystem: mockFS,
            notificationController: MockNotificationController()
        )
        try await Task.sleep(nanoseconds: 10_000_000)

        let initialTabCount = model.tabs.count

        model.newTab()
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(model.tabs.count, initialTabCount + 1, "newTab should add one tab")
        XCTAssertFalse(model.localItems.isEmpty, "localItems should not be empty after newTab populates them")
        XCTAssertEqual(
            model.localItems.map(\.name),
            expectedItems.map(\.name),
            "localItems should match mock filesystem"
        )
    }

    // MARK: - Close Tab Tests

    func testCloseConnectedTabShowsConfirmation() async throws {
        let model = try await self.makeModelWithTwoTabs(secondTabState: .connected)

        let tabCountBefore = model.tabs.count
        model.closeSelectedTab()

        XCTAssertNotNil(model.pendingCloseTabID, "Connected tab close should set pendingCloseTabID")
        XCTAssertEqual(model.tabs.count, tabCountBefore, "Connected tab should not be removed until confirmed")
    }

    func testCloseDisconnectedTabRemovesImmediately() async throws {
        let model = try await self.makeModelWithTwoTabs(secondTabState: .disconnected)

        let tabCountBefore = model.tabs.count
        model.closeSelectedTab()

        XCTAssertNil(model.pendingCloseTabID, "Disconnected tab close should not set pendingCloseTabID")
        XCTAssertEqual(model.tabs.count, tabCountBefore - 1, "Disconnected tab should be removed immediately")
    }

    func testConfirmCloseConnectedTabDisconnectsRemoteSession() async throws {
        let remoteFileSystem = MockRemoteFileSystemClient()
        let model = try await self.makeModelWithTwoTabs(
            secondTabState: .connected,
            remoteFileSystem: remoteFileSystem
        )

        model.closeSelectedTab()
        model.confirmCloseTab()
        try await Task.sleep(nanoseconds: 10_000_000)

        let disconnectCallCount = await remoteFileSystem.disconnectCallCount
        XCTAssertEqual(disconnectCallCount, 1, "Confirming close for a connected tab should disconnect its remote session")
    }

    func testCannotCloseLastTab() async throws {
        let model = self.makeModel()
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(model.tabs.count, 1)
        model.closeSelectedTab()

        XCTAssertEqual(model.tabs.count, 1, "Last tab must not be closed")
    }

    // MARK: - Helpers

    private func makeModel(remoteFileSystem: RemoteFileSystemClient = MockRemoteFileSystemClient()) -> AppModel {
        AppModel(
            profileRepository: InMemoryServerProfileRepository(),
            preferencesRepository: InMemoryViewPreferencesRepository(),
            transferHistoryRepository: InMemoryTransferHistoryRepository(),
            bookmarkRepository: InMemoryServerBookmarkRepository(),
            recentRepository: InMemoryRecentServerRepository(),
            localFileSystem: MockLocalFileSystemClient { _, _ in [] },
            remoteFileSystem: remoteFileSystem,
            notificationController: MockNotificationController()
        )
    }

    private func makeModelWithTwoTabs(
        secondTabState: ConnectionState,
        remoteFileSystem: RemoteFileSystemClient = MockRemoteFileSystemClient()
    ) async throws -> AppModel {
        let model = self.makeModel(remoteFileSystem: remoteFileSystem)
        try await Task.sleep(nanoseconds: 10_000_000)

        model.newTab()
        try await Task.sleep(nanoseconds: 10_000_000)

        // Set the second (now selected) tab's session state
        let selectedID = try XCTUnwrap(model.selectedTabID)
        let index = try XCTUnwrap(model.tabs.firstIndex(where: { $0.id == selectedID }))
        model.tabs[index].session.state = secondTabState

        return model
    }
}

private final class MockLocalFileSystemClient: LocalFileSystemClient, @unchecked Sendable {
    private let listDirectoryBlock: @Sendable (String, FileListPreferences) async throws -> [FileItem]

    init(listDirectory: @escaping @Sendable (String, FileListPreferences) async throws -> [FileItem]) {
        self.listDirectoryBlock = listDirectory
    }

    func listDirectory(at path: String, preferences: FileListPreferences) async throws -> [FileItem] {
        try await self.listDirectoryBlock(path, preferences)
    }

    func createFolder(named _: String, in _: String) async throws {}
    func renameItem(at _: String, to _: String) async throws {}
    func deleteItem(at _: String) async throws {}
    func itemExists(at _: String) async -> Bool {
        true
    }
}

private actor MockRemoteFileSystemClient: RemoteFileSystemClient {
    private var disconnectCalls = 0

    var disconnectCallCount: Int {
        self.disconnectCalls
    }

    func connect(to profile: ServerProfile) async throws -> ConnectionSession {
        ConnectionSession(serverID: profile.id, state: .connected, protocolKind: profile.protocolKind)
    }

    func disconnect(session _: ConnectionSession) async throws {
        self.disconnectCalls += 1
    }

    func listDirectory(at _: String, profile _: ServerProfile, session _: ConnectionSession, preferences _: FileListPreferences) async throws -> [FileItem] {
        []
    }

    func createFolder(named _: String, in _: String, profile _: ServerProfile, session _: ConnectionSession) async throws {}
    func renameItem(at _: String, to _: String, profile _: ServerProfile, session _: ConnectionSession) async throws {}
    func deleteItem(at _: String, profile _: ServerProfile, session _: ConnectionSession) async throws {}

    func itemExists(at _: String, profile _: ServerProfile, session _: ConnectionSession) async throws -> Bool {
        false
    }
}

private final class MockNotificationController: AppNotificationControlling, @unchecked Sendable {
    func requestPermissionIfNeeded() async {}
    func notifyIfBackground(isEnabled _: Bool, title _: String, body _: String, identifier _: String) {}
}
