import Foundation

public enum AppIconVariant: String, CaseIterable, Codable, Sendable, Identifiable {
    case light
    case dark

    public var id: String {
        self.rawValue
    }

    public var displayName: String {
        switch self {
        case .light:
            LocalizationManager.shared.localized("appearance.light")
        case .dark:
            LocalizationManager.shared.localized("appearance.dark")
        }
    }
}

public enum AppThemeVariant: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case light
    case dark

    public var id: String {
        self.rawValue
    }

    public var displayName: String {
        switch self {
        case .system:
            LocalizationManager.shared.localized("appearance.system")
        case .light:
            LocalizationManager.shared.localized("appearance.light")
        case .dark:
            LocalizationManager.shared.localized("appearance.dark")
        }
    }
}

public struct ViewPreferences: Codable, Equatable, Sendable {
    public var fileList: FileListPreferences
    public var showInspector: Bool
    public var showTransferQueue: Bool
    public var showSidebar: Bool
    public var transferConcurrency: Int
    public var confirmBeforeDelete: Bool
    public var confirmBeforeOverwrite: Bool
    public var remoteBackendKind: RemoteBackendKind
    public var appIconVariant: AppIconVariant
    public var appThemeVariant: AppThemeVariant
    public var checkForUpdatesOnStartup: Bool
    public var backgroundNotificationsEnabled: Bool
    public var localizedLanguage: SupportedLanguage
    public var hasSetLanguageExplicitly: Bool

    enum CodingKeys: String, CodingKey {
        case fileList
        case showInspector
        case showTransferQueue
        case showSidebar
        case transferConcurrency
        case confirmBeforeDelete
        case confirmBeforeOverwrite
        case remoteBackendKind
        case appIconVariant
        case appThemeVariant
        case checkForUpdatesOnStartup
        case backgroundNotificationsEnabled
        case localizedLanguage
        case hasSetLanguageExplicitly
    }

    public init(
        fileList: FileListPreferences = FileListPreferences(),
        showInspector: Bool = true,
        showTransferQueue: Bool = true,
        showSidebar: Bool = true,
        transferConcurrency: Int = 3,
        confirmBeforeDelete: Bool = true,
        confirmBeforeOverwrite: Bool = true,
        remoteBackendKind: RemoteBackendKind = .systemSSH,
        appIconVariant: AppIconVariant = .light,
        appThemeVariant: AppThemeVariant = .system,
        checkForUpdatesOnStartup: Bool = true,
        backgroundNotificationsEnabled: Bool = true,
        localizedLanguage: SupportedLanguage = .english,
        hasSetLanguageExplicitly: Bool = false
    ) {
        self.fileList = fileList
        self.showInspector = showInspector
        self.showTransferQueue = showTransferQueue
        self.showSidebar = showSidebar
        self.transferConcurrency = transferConcurrency
        self.confirmBeforeDelete = confirmBeforeDelete
        self.confirmBeforeOverwrite = confirmBeforeOverwrite
        self.remoteBackendKind = remoteBackendKind
        self.appIconVariant = appIconVariant
        self.appThemeVariant = appThemeVariant
        self.checkForUpdatesOnStartup = checkForUpdatesOnStartup
        self.backgroundNotificationsEnabled = backgroundNotificationsEnabled
        self.localizedLanguage = localizedLanguage
        self.hasSetLanguageExplicitly = hasSetLanguageExplicitly
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fileList = try container.decodeIfPresent(FileListPreferences.self, forKey: .fileList) ?? FileListPreferences()
        self.showInspector = try container.decodeIfPresent(Bool.self, forKey: .showInspector) ?? true
        self.showTransferQueue = try container.decodeIfPresent(Bool.self, forKey: .showTransferQueue) ?? true
        self.showSidebar = try container.decodeIfPresent(Bool.self, forKey: .showSidebar) ?? true
        self.transferConcurrency = try container.decodeIfPresent(Int.self, forKey: .transferConcurrency) ?? 3
        self.confirmBeforeDelete = try container.decodeIfPresent(Bool.self, forKey: .confirmBeforeDelete) ?? true
        self.confirmBeforeOverwrite = try container.decodeIfPresent(Bool.self, forKey: .confirmBeforeOverwrite) ?? true
        self.remoteBackendKind = try container.decodeIfPresent(RemoteBackendKind.self, forKey: .remoteBackendKind) ?? .systemSSH
        self.appIconVariant = try container.decodeIfPresent(AppIconVariant.self, forKey: .appIconVariant) ?? .light
        self.appThemeVariant = try container.decodeIfPresent(AppThemeVariant.self, forKey: .appThemeVariant) ?? .system
        self.checkForUpdatesOnStartup = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdatesOnStartup) ?? true
        self.backgroundNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .backgroundNotificationsEnabled) ?? true
        self.localizedLanguage = try container.decodeIfPresent(SupportedLanguage.self, forKey: .localizedLanguage) ?? .english
        self.hasSetLanguageExplicitly = try container.decodeIfPresent(Bool.self, forKey: .hasSetLanguageExplicitly) ?? false
    }
}
