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
                    TextField(LocalizationManager.shared.localized("profile.host"), text: self.$draft.host)
                    Picker(LocalizationManager.shared.localized("profile.protocol"), selection: self.$draft.protocolKind) {
                        ForEach(TransferProtocolKind.allCases) { protocolKind in
                            Text(protocolKind.rawValue.uppercased()).tag(protocolKind)
                        }
                    }
                    Stepper(value: self.$draft.port, in: 1 ... 65535) {
                        LabeledContent(LocalizationManager.shared.localized("profile.port"), value: "\(self.draft.port)")
                    }
                    TextField(LocalizationManager.shared.localized("profile.group"), text: self.$draft.groupName)
                    Toggle(LocalizationManager.shared.localized("profile.favorite"), isOn: self.$draft.isFavorite)
                }

                Section(LocalizationManager.shared.localized("profile.section.authentication")) {
                    TextField(LocalizationManager.shared.localized("profile.username"), text: self.$draft.username)
                    Picker(LocalizationManager.shared.localized("profile.method"), selection: self.$draft.authKind) {
                        ForEach(ServerProfileDraft.AuthKind.allCases) { method in
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
