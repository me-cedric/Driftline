import AppKit
import DriftlineCore
import SwiftUI

struct ServerProfileEditorView: View {
    @Binding var draft: ServerProfileDraft
    var savesAndConnects: Bool
    var errorMessage: String?
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(LocalizationManager.shared.localized("profile.section.server")) {
                    TextField(LocalizationManager.shared.localized("profile.displayName"), text: self.$draft.displayName)
                    TextField(LocalizationManager.shared.localized("profile.host"), text: self.$draft.host, prompt: Text(verbatim: "sftp.example.com"))
                        .onChange(of: self.draft.host) { _, host in
                            // A pasted URL fills protocol, port, user and path at once.
                            if host.contains("://") {
                                self.draft.applyAddressFromHost()
                            }
                        }
                    Picker(LocalizationManager.shared.localized("profile.protocol"), selection: Binding(
                        get: { self.draft.protocolKind },
                        set: { self.draft.changeProtocol(to: $0) }
                    )) {
                        ForEach(TransferProtocolKind.allCases) { protocolKind in
                            Text(protocolKind.rawValue.uppercased()).tag(protocolKind)
                        }
                    }
                    TextField(LocalizationManager.shared.localized("profile.port"), value: self.$draft.port, format: .number.grouping(.never))
                    if self.draft.protocolKind == .ftp {
                        Label(LocalizationManager.shared.localized("profile.ftpPlainWarning"), systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if self.draft.protocolKind == .ftps {
                        Picker(LocalizationManager.shared.localized("profile.ftpsMode"), selection: Binding(
                            get: { self.draft.ftpsImplicitTLS },
                            set: { self.draft.changeFTPSMode(implicitTLS: $0) }
                        )) {
                            Text(LocalizationManager.shared.localized("profile.ftpsMode.explicit")).tag(false)
                            Text(LocalizationManager.shared.localized("profile.ftpsMode.implicit")).tag(true)
                        }
                        Text(LocalizationManager.shared.localized("profile.ftpsModeNote"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField(LocalizationManager.shared.localized("profile.group"), text: self.$draft.groupName)
                    Toggle(LocalizationManager.shared.localized("profile.favorite"), isOn: self.$draft.isFavorite)
                }

                Section(LocalizationManager.shared.localized("profile.section.authentication")) {
                    TextField(LocalizationManager.shared.localized("profile.username"), text: self.$draft.username)
                    Picker(LocalizationManager.shared.localized("profile.method"), selection: self.$draft.authKind) {
                        ForEach(ServerProfileDraft.authKinds(for: self.draft.protocolKind)) { method in
                            Text(method.localizedTitle).tag(method)
                        }
                    }
                    if self.draft.authKind == .privateKey {
                        HStack {
                            TextField(LocalizationManager.shared.localized("profile.privateKeyPath"), text: self.$draft.privateKeyPath)
                            Button(LocalizationManager.shared.localized("profile.choose")) {
                                self.choosePrivateKey()
                            }
                        }
                        Toggle(LocalizationManager.shared.localized("profile.storePassphrase"), isOn: self.$draft.storePassphrase)
                        if self.draft.storePassphrase {
                            SecureField(LocalizationManager.shared.localized("profile.privateKeyPassphrase"), text: self.$draft.passphrase)
                        }
                    }
                    if self.draft.authKind == .password {
                        SecureField(LocalizationManager.shared.localized("profile.password"), text: self.$draft.password)
                        Text(LocalizationManager.shared.localized("profile.passwordNote"))
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.68))
                    }
                }

                Section(LocalizationManager.shared.localized("profile.section.paths")) {
                    TextField(LocalizationManager.shared.localized("profile.remotePath"), text: self.$draft.remoteDefaultPath)
                    HStack {
                        TextField(LocalizationManager.shared.localized("profile.localPath"), text: self.$draft.localDefaultPath)
                        Button(LocalizationManager.shared.localized("profile.choose")) {
                            self.chooseLocalFolder()
                        }
                    }
                }

                Section(LocalizationManager.shared.localized("profile.section.metadata")) {
                    TextField(LocalizationManager.shared.localized("profile.tags"), text: self.$draft.tags, prompt: Text(LocalizationManager.shared.localized("profile.tagsPrompt")))
                    TextField(LocalizationManager.shared.localized("profile.notes"), text: self.$draft.notes, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(self.savesAndConnects ? LocalizationManager.shared.localized("menu.newConnection") : (self.draft.displayName.isEmpty ? LocalizationManager.shared.localized("profile.newServer") : self.draft.displayName))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizationManager.shared.localized("delete.cancel"), action: self.onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(self.savesAndConnects ? LocalizationManager.shared.localized("profile.saveConnect") : LocalizationManager.shared.localized("profile.save"), action: self.onSave)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 520, height: 620)
    }

    private func choosePrivateKey() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            self.draft.privateKeyPath = url.path
        }
    }

    private func chooseLocalFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: NSString(string: self.draft.localDefaultPath).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            self.draft.localDefaultPath = url.path
        }
    }
}
