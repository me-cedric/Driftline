import DriftlineCore
import SwiftUI

struct AboutView: View {
    var isCheckingForUpdates = false
    var onCheckForUpdates: () -> Void = {}
    var onRevealDiagnostics: () -> Void = {}

    var body: some View {
        AppAboutContent(
            isCheckingForUpdates: self.isCheckingForUpdates,
            onCheckForUpdates: self.onCheckForUpdates,
            onRevealDiagnostics: self.onRevealDiagnostics
        )
        .padding(32)
        .frame(width: 380)
    }
}

struct AppAboutContent: View {
    var isCheckingForUpdates = false
    var onCheckForUpdates: () -> Void = {}
    var onRevealDiagnostics: () -> Void = {}

    private let donationURL = URL(string: "https://ko-fi.com/mecedric")!

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 54))
                .foregroundStyle(.blue)

            VStack(spacing: 4) {
                Text(AppMetadata.name)
                    .font(.largeTitle.bold())
                Text(AppMetadata.versionDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(LocalizationManager.shared.localized("about.tagline"))
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 4)

            Text(LocalizationManager.shared.localized("about.freeMessage"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: self.donationURL) {
                Label(LocalizationManager.shared.localized("about.donate"), systemImage: "heart.fill")
            }
            .buttonStyle(.borderedProminent)

            HStack {
                Button {
                    self.onCheckForUpdates()
                } label: {
                    Label(self.isCheckingForUpdates ? LocalizationManager.shared.localized("about.checking") : LocalizationManager.shared.localized("about.checkForUpdates"), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(self.isCheckingForUpdates)

                Button {
                    self.onRevealDiagnostics()
                } label: {
                    Label(LocalizationManager.shared.localized("about.diagnostics"), systemImage: "doc.text.magnifyingglass")
                }
            }

            Link("GitHub", destination: URL(string: "https://github.com/me-cedric/Driftline")!)
                .font(.caption)
        }
    }
}

enum AppMetadata {
    static var name: String {
        self.bundleString("CFBundleDisplayName")
            ?? self.bundleString("CFBundleName")
            ?? "Driftline"
    }

    static var versionDisplay: String {
        String(format: LocalizationManager.shared.localized("about.version"), self.shortVersion, self.buildNumber)
    }

    static var shortVersion: String {
        self.bundleString("CFBundleShortVersionString") ?? "0.5.0"
    }

    static var buildNumber: String {
        self.bundleString("CFBundleVersion") ?? "5"
    }

    static var updateCurrentVersion: String {
        self.bundleString("CFBundleShortVersionString") ?? "0.5.0"
    }

    private static func bundleString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
