import Foundation

public protocol ServerProfileRepository: Sendable {
    func list() async throws -> [ServerProfile]
    func save(_ profile: ServerProfile) async throws
    func delete(id: ServerProfileID) async throws
}

public actor InMemoryServerProfileRepository: ServerProfileRepository {
    private var profiles: [ServerProfileID: ServerProfile] = [:]

    public init(profiles: [ServerProfile] = []) {
        self.profiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    public func list() async throws -> [ServerProfile] {
        profiles.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func save(_ profile: ServerProfile) async throws {
        var updated = profile
        updated.updatedAt = Date()
        profiles[updated.id] = updated
    }

    public func delete(id: ServerProfileID) async throws {
        profiles.removeValue(forKey: id)
    }
}

public actor JSONServerProfileRepository: ServerProfileRepository {
    private let store: JSONFileStore<[ServerProfile]>

    public init(url: URL = DriftlineStoragePaths.profilesURL) {
        self.store = JSONFileStore(url: url)
    }

    public func list() async throws -> [ServerProfile] {
        let profiles = try await store.load(default: [])
        return profiles.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func save(_ profile: ServerProfile) async throws {
        var profiles = try await store.load(default: [])
        var updated = profile
        updated.updatedAt = Date()
        if let index = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[index] = updated
        } else {
            profiles.append(updated)
        }
        try await store.save(profiles)
    }

    public func delete(id: ServerProfileID) async throws {
        var profiles = try await store.load(default: [])
        profiles.removeAll { $0.id == id }
        try await store.save(profiles)
    }
}

public protocol TransferHistoryRepository: Sendable {
    func append(_ job: TransferJob) async throws
    func list(limit: Int) async throws -> [TransferJob]
    func clear(where shouldClear: @Sendable (TransferJob) -> Bool) async throws
}

public actor InMemoryTransferHistoryRepository: TransferHistoryRepository {
    private var jobs: [TransferJob] = []

    public init() {}

    public func append(_ job: TransferJob) async throws {
        jobs.append(job)
    }

    public func list(limit: Int) async throws -> [TransferJob] {
        Array(jobs.suffix(limit).reversed())
    }

    public func clear(where shouldClear: @Sendable (TransferJob) -> Bool) async throws {
        jobs.removeAll(where: shouldClear)
    }
}

public actor JSONTransferHistoryRepository: TransferHistoryRepository {
    private let store: JSONFileStore<[TransferJob]>

    public init(url: URL = DriftlineStoragePaths.transferHistoryURL) {
        self.store = JSONFileStore(url: url)
    }

    public func append(_ job: TransferJob) async throws {
        var jobs = try await store.load(default: [])
        jobs.append(job)
        try await store.save(jobs)
    }

    public func list(limit: Int) async throws -> [TransferJob] {
        let jobs = try await store.load(default: [])
        return Array(jobs.suffix(limit).reversed())
    }

    public func clear(where shouldClear: @Sendable (TransferJob) -> Bool) async throws {
        var jobs = try await store.load(default: [])
        jobs.removeAll(where: shouldClear)
        try await store.save(jobs)
    }
}

public protocol ViewPreferencesRepository: Sendable {
    func load() async throws -> ViewPreferences
    func save(_ preferences: ViewPreferences) async throws
}

public actor JSONViewPreferencesRepository: ViewPreferencesRepository {
    private let store: JSONFileStore<ViewPreferences>

    public init(url: URL = DriftlineStoragePaths.preferencesURL) {
        self.store = JSONFileStore(url: url)
    }

    public func load() async throws -> ViewPreferences {
        try await store.load(default: ViewPreferences())
    }

    public func save(_ preferences: ViewPreferences) async throws {
        try await store.save(preferences)
    }
}

public protocol ServerBookmarkRepository: Sendable {
    func list() async throws -> [ServerBookmark]
    func save(_ bookmark: ServerBookmark) async throws
    func delete(id: UUID) async throws
}

public actor JSONServerBookmarkRepository: ServerBookmarkRepository {
    private let store: JSONFileStore<[ServerBookmark]>

    public init(url: URL = DriftlineStoragePaths.bookmarksURL) {
        self.store = JSONFileStore(url: url)
    }

    public func list() async throws -> [ServerBookmark] {
        try await store.load(default: []).sorted {
            ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt)
        }
    }

    public func save(_ bookmark: ServerBookmark) async throws {
        var bookmarks = try await store.load(default: [])
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[index] = bookmark
        } else {
            bookmarks.append(bookmark)
        }
        try await store.save(bookmarks)
    }

    public func delete(id: UUID) async throws {
        var bookmarks = try await store.load(default: [])
        bookmarks.removeAll { $0.id == id }
        try await store.save(bookmarks)
    }
}

public protocol RecentServerRepository: Sendable {
    func list(limit: Int) async throws -> [RecentServer]
    func record(_ recent: RecentServer, limit: Int) async throws
}

public actor JSONRecentServerRepository: RecentServerRepository {
    private let store: JSONFileStore<[RecentServer]>

    public init(url: URL = DriftlineStoragePaths.recentsURL) {
        self.store = JSONFileStore(url: url)
    }

    public func list(limit: Int) async throws -> [RecentServer] {
        let recents = try await store.load(default: [])
        return Array(recents.sorted { $0.connectedAt > $1.connectedAt }.prefix(limit))
    }

    public func record(_ recent: RecentServer, limit: Int = 20) async throws {
        var recents = try await store.load(default: [])
        recents.removeAll { $0.profileID == recent.profileID }
        recents.insert(recent, at: 0)
        recents = Array(recents.prefix(limit))
        try await store.save(recents)
    }
}
