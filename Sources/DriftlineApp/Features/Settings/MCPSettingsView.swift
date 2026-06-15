import AppKit
import DriftlineCore
import DriftlineMCP
import SwiftUI

struct MCPSettingsView: View {
    @Bindable var model: AppModel
    @State private var tokenText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(title: loc("settings.mcp.server")) {
                    Toggle(loc("settings.mcp.enabled"), isOn: self.$model.mcpConfiguration.enabled)
                    Toggle(loc("settings.mcp.destructive"), isOn: self.$model.mcpConfiguration.allowDestructiveOperations)
                }

                SettingsSection(title: loc("settings.mcp.http")) {
                    Toggle(loc("settings.mcp.httpEnabled"), isOn: self.$model.mcpConfiguration.httpEnabled)

                    HStack(spacing: 12) {
                        Text(loc("settings.mcp.port"))
                            .frame(width: 90, alignment: .leading)
                        Stepper("\(self.model.mcpConfiguration.httpPort)", value: self.$model.mcpConfiguration.httpPort, in: 1024 ... 65535)
                    }

                    HStack(spacing: 8) {
                        Button(loc("settings.mcp.revealToken")) {
                            Task {
                                self.tokenText = await self.model.readMCPHTTPToken() ?? ""
                            }
                        }
                        Button(loc("settings.mcp.regenerateToken")) {
                            self.model.regenerateMCPHTTPToken()
                            self.tokenText = ""
                        }
                    }

                    if !self.tokenText.isEmpty {
                        Text(self.tokenText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }

                SettingsSection(title: loc("settings.mcp.localRoots")) {
                    if self.model.mcpConfiguration.allowedLocalRoots.isEmpty {
                        Text(loc("settings.mcp.defaultRoot"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(self.model.mcpConfiguration.allowedLocalRoots, id: \.self) { root in
                        HStack {
                            Text(root)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                self.model.mcpConfiguration.allowedLocalRoots.removeAll { $0 == root }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(loc("settings.mcp.removeRoot"))
                        }
                    }

                    Button {
                        self.addRoot()
                    } label: {
                        Label(loc("settings.mcp.addRoot"), systemImage: "plus")
                    }
                }

                SettingsSection(title: loc("settings.mcp.clientConfig")) {
                    TextEditor(text: .constant(self.model.mcpClientConfigurationSnippet()))
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 104)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(self.model.mcpClientConfigurationSnippet(), forType: .string)
                    } label: {
                        Label(loc("settings.mcp.copyConfig"), systemImage: "doc.on.doc")
                    }
                }
            }
            .padding(.top, 12)
        }
    }

    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = loc("settings.mcp.addRoot")
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.standardizedFileURL.path
            if !self.model.mcpConfiguration.allowedLocalRoots.contains(path) {
                self.model.mcpConfiguration.allowedLocalRoots.append(path)
            }
        }
    }
}
