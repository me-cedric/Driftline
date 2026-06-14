import Foundation

public struct AppUpdate: Equatable, Sendable {
    public var latestVersion: String
    public var currentVersion: String
    public var releaseURL: URL
    public var assetURL: URL?
    public var releaseName: String?
    public var publishedAt: Date?

    public var isNewer: Bool {
        VersionComparator.isVersion(self.latestVersion, newerThan: self.currentVersion)
    }

    public init(latestVersion: String, currentVersion: String, releaseURL: URL, assetURL: URL?, releaseName: String?, publishedAt: Date?) {
        self.latestVersion = latestVersion
        self.currentVersion = currentVersion
        self.releaseURL = releaseURL
        self.assetURL = assetURL
        self.releaseName = releaseName
        self.publishedAt = publishedAt
    }
}

public struct GitHubRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public var name: String
        public var browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    public var tagName: String
    public var name: String?
    public var htmlURL: URL
    public var publishedAt: Date?
    public var assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

public struct VersionComparator: Sendable {
    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = self.parts(from: candidate)
        let currentParts = self.parts(from: current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0 ..< count {
            let lhs = index < candidateParts.count ? candidateParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs > rhs { return true }
            if lhs < rhs { return false }
        }
        return false
    }

    private static func parts(from version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        return normalized
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { component in
                let numericPrefix = component.prefix { $0.isNumber }
                return Int(numericPrefix) ?? 0
            }
    }
}

public struct GitHubUpdateChecker: Sendable {
    public var owner: String
    public var repository: String
    public var currentVersion: String
    public var session: URLSession

    public init(owner: String = "me-cedric", repository: String = "Driftline", currentVersion: String, session: URLSession = .shared) {
        self.owner = owner
        self.repository = repository
        self.currentVersion = currentVersion
        self.session = session
    }

    public func latestUpdate() async throws -> AppUpdate {
        let release = try await self.latestRelease()
        return AppUpdate(
            latestVersion: release.tagName,
            currentVersion: self.currentVersion,
            releaseURL: release.htmlURL,
            assetURL: self.preferredAssetURL(from: release.assets),
            releaseName: release.name,
            publishedAt: release.publishedAt
        )
    }

    private func latestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(self.owner)/\(self.repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Driftline update checker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode
        else {
            throw AppUpdateError.requestFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    private func preferredAssetURL(from assets: [GitHubRelease.Asset]) -> URL? {
        let preferredExtensions = [".dmg", ".zip"]
        return assets.first { asset in
            preferredExtensions.contains { asset.name.localizedCaseInsensitiveContains($0) }
        }?.browserDownloadURL
    }
}

public enum AppUpdateError: LocalizedError, Sendable {
    case requestFailed

    public var errorDescription: String? {
        switch self {
        case .requestFailed:
            "The update server returned an unexpected response."
        }
    }
}
