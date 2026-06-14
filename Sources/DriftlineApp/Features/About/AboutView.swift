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

            Text("Native file transfer, calmly secure.")
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 4)

            Text("Driftline is entirely free. If it helps you, feel free to donate.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: self.donationURL) {
                Label("Donate on Ko-fi", systemImage: "heart.fill")
            }
            .buttonStyle(.borderedProminent)

            HStack {
                Button {
                    self.onCheckForUpdates()
                } label: {
                    Label(self.isCheckingForUpdates ? "Checking..." : "Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(self.isCheckingForUpdates)

                Button {
                    self.onRevealDiagnostics()
                } label: {
                    Label("Diagnostics", systemImage: "doc.text.magnifyingglass")
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
        "Version \(self.shortVersion) (\(self.buildNumber))"
    }

    static var shortVersion: String {
        self.bundleString("CFBundleShortVersionString") ?? "0.4.0"
    }

    static var buildNumber: String {
        self.bundleString("CFBundleVersion") ?? "4"
    }

    static var updateCurrentVersion: String {
        self.bundleString("CFBundleShortVersionString") ?? "0.4.0"
    }

    private static func bundleString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
