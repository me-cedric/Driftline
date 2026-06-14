import SwiftUI

struct AboutView: View {
    var body: some View {
        AppAboutContent()
            .padding(32)
            .frame(width: 380)
    }
}

struct AppAboutContent: View {
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
        let version = self.bundleString("CFBundleShortVersionString") ?? "0.2.0"
        let build = self.bundleString("CFBundleVersion") ?? "2"
        return "Version \(version) (\(build))"
    }

    private static func bundleString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
