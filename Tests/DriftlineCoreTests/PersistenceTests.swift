@testable import DriftlineCore
import XCTest

final class PersistenceTests: XCTestCase {
    func testJSONServerProfileRepositoryRoundTripsAndDeletesProfiles() async throws {
        let url = self.temporaryFileURL("profiles.json")
        let repository = JSONServerProfileRepository(url: url)
        let profile = ServerProfile(
            displayName: "Production",
            host: "prod.example.com",
            protocolKind: .sftp,
            username: "deploy",
            authenticationMethod: .agent,
            tags: ["prod"],
            isFavorite: true
        )

        try await repository.save(profile)
        let loaded = try await repository.list()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.displayName, "Production")
        XCTAssertEqual(loaded.first?.authenticationMethod, .agent)

        try await repository.delete(id: profile.id)
        let afterDelete = try await repository.list()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testJSONViewPreferencesRepositoryRoundTripsPreferences() async throws {
        let url = self.temporaryFileURL("preferences.json")
        let repository = JSONViewPreferencesRepository(url: url)
        let preferences = ViewPreferences(
            fileList: FileListPreferences(showHiddenFiles: true, showFileExtensions: false, sortKey: .modifiedAt, sortAscending: false, foldersFirst: false),
            showInspector: false,
            showTransferQueue: true,
            showSidebar: true,
            transferConcurrency: 6,
            confirmBeforeDelete: true,
            confirmBeforeOverwrite: false,
            appIconVariant: .dark,
            appThemeVariant: .dark
        )

        try await repository.save(preferences)
        let loaded = try await repository.load()

        XCTAssertEqual(loaded, preferences)
    }

    func testViewPreferencesDecodesOlderPayloadWithoutRemoteBackend() throws {
        let payload = Data("""
        {
          "fileList": {
            "showHiddenFiles": true,
            "showFileExtensions": true,
            "sortKey": "name",
            "sortAscending": true,
            "foldersFirst": true,
            "compactRows": false
          },
          "showInspector": true,
          "showTransferQueue": true,
          "showSidebar": true,
          "transferConcurrency": 2,
          "confirmBeforeDelete": true,
          "confirmBeforeOverwrite": true
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(ViewPreferences.self, from: payload)

        XCTAssertEqual(decoded.remoteBackendKind, .systemSSH)
        XCTAssertEqual(decoded.appIconVariant, .light)
        XCTAssertEqual(decoded.appThemeVariant, .system)
        XCTAssertEqual(decoded.transferConcurrency, 2)
    }

    func testJSONTransferHistoryRepositoryAppendsListsAndClears() async throws {
        let url = self.temporaryFileURL("history.json")
        let repository = JSONTransferHistoryRepository(url: url)
        let failed = TransferJob(direction: .upload, sourcePath: "/a", destinationPath: "/b", status: .failed(message: "Nope"))
        let succeeded = TransferJob(direction: .download, sourcePath: "/c", destinationPath: "/d", status: .succeeded)

        try await repository.append(failed)
        try await repository.append(succeeded)
        var jobs = try await repository.list(limit: 10)

        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs.first?.destinationPath, "/d")

        try await repository.clear { job in
            if case .failed = job.status { return true }
            return false
        }
        jobs = try await repository.list(limit: 10)

        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?.status, .succeeded)
    }

    func testBookmarkRepositoryRoundTripsAndDeletesBookmarks() async throws {
        let url = self.temporaryFileURL("bookmarks.json")
        let repository = JSONServerBookmarkRepository(url: url)
        let profileID = ServerProfileID()
        let bookmark = ServerBookmark(profileID: profileID, name: "Web Root", localPath: "/Users/me/Sites", remotePath: "/var/www")

        try await repository.save(bookmark)
        let loaded = try await repository.list()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Web Root")
        XCTAssertEqual(loaded.first?.remotePath, "/var/www")

        try await repository.delete(id: bookmark.id)
        let afterDelete = try await repository.list()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testRecentRepositoryKeepsMostRecentPerProfileAndLimit() async throws {
        let url = self.temporaryFileURL("recents.json")
        let repository = JSONRecentServerRepository(url: url)
        let first = ServerProfileID()
        let second = ServerProfileID()

        try await repository.record(RecentServer(profileID: first, displayName: "First", host: "a.example.com", protocolKind: .sftp, localPath: "/a", remotePath: "/a"), limit: 2)
        try await repository.record(RecentServer(profileID: second, displayName: "Second", host: "b.example.com", protocolKind: .sftp, localPath: "/b", remotePath: "/b"), limit: 2)
        try await repository.record(RecentServer(profileID: first, displayName: "First Updated", host: "a.example.com", protocolKind: .sftp, localPath: "/c", remotePath: "/c"), limit: 2)

        let recents = try await repository.list(limit: 2)

        XCTAssertEqual(recents.count, 2)
        XCTAssertEqual(recents.first?.displayName, "First Updated")
        XCTAssertEqual(recents.filter { $0.profileID == first }.count, 1)
    }

    func testRecentRepositoryDeletesProfileRecents() async throws {
        let url = self.temporaryFileURL("recents.json")
        let repository = JSONRecentServerRepository(url: url)
        let first = ServerProfileID()
        let second = ServerProfileID()

        try await repository.record(RecentServer(profileID: first, displayName: "First", host: "a.example.com", protocolKind: .sftp, localPath: "/a", remotePath: "/a"), limit: 10)
        try await repository.record(RecentServer(profileID: second, displayName: "Second", host: "b.example.com", protocolKind: .sftp, localPath: "/b", remotePath: "/b"), limit: 10)

        try await repository.delete(profileID: first)
        let recents = try await repository.list(limit: 10)

        XCTAssertEqual(recents.count, 1)
        XCTAssertEqual(recents.first?.profileID, second)
    }

    func testJSONHostTrustStoreDetectsUnknownTrustedAndChangedFingerprints() async throws {
        let url = self.temporaryFileURL("host-trust.json")
        let store = JSONHostTrustStore(url: url)

        let unknown = try await store.verificationResult(host: "example.com", port: 22, algorithm: "SHA256", fingerprint: "aaa")
        XCTAssertEqual(unknown, .unknown(fingerprint: "aaa"))

        try await store.trust(HostTrustRecord(host: "example.com", port: 22, algorithm: "SHA256", fingerprint: "aaa"))

        let trusted = try await store.verificationResult(host: "example.com", port: 22, algorithm: "SHA256", fingerprint: "aaa")
        XCTAssertEqual(trusted, .trusted)

        let changed = try await store.verificationResult(host: "example.com", port: 22, algorithm: "SHA256", fingerprint: "bbb")
        XCTAssertEqual(changed, .changed(previous: "aaa", current: "bbb"))
    }

    private func temporaryFileURL(_ filename: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftlineTests-\(UUID().uuidString)", isDirectory: true)
        return directory.appendingPathComponent(filename)
    }
}
