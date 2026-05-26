import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 54))
                .foregroundStyle(.teal)
            Text("Driftline")
                .font(.largeTitle.bold())
            Text("Native file transfer, calmly secure.")
                .foregroundStyle(.secondary)
            Text("Version 0.1.0 (1)")
                .font(.caption)
            Link("GitHub", destination: URL(string: "https://github.com/OWNER/Driftline")!)
            Link("Security Policy", destination: URL(string: "https://github.com/OWNER/Driftline/security/policy")!)
        }
        .padding(32)
        .frame(width: 360)
    }
}
