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
                Section("Server") {
                    TextField("Display Name", text: self.$draft.displayName)
                    TextField("Host", text: self.$draft.host)
                    Picker("Protocol", selection: self.$draft.protocolKind) {
                        ForEach(TransferProtocolKind.allCases) { protocolKind in
                            Text(protocolKind.rawValue.uppercased()).tag(protocolKind)
                        }
                    }
                    Stepper(value: self.$draft.port, in: 1 ... 65535) {
                        LabeledContent("Port", value: "\(self.draft.port)")
                    }
                    TextField("Group", text: self.$draft.groupName)
                    Toggle("Favorite", isOn: self.$draft.isFavorite)
                }

                Section("Authentication") {
                    TextField("Username", text: self.$draft.username)
                    Picker("Method", selection: self.$draft.authKind) {
                        ForEach(ServerProfileDraft.AuthKind.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    if self.draft.authKind == .privateKey {
                        HStack {
                            TextField("Private Key Path", text: self.$draft.privateKeyPath)
                            Button("Choose...") {
                                self.choosePrivateKey()
                            }
                        }
                        Toggle("Store passphrase in Keychain", isOn: self.$draft.storePassphrase)
                        if self.draft.storePassphrase {
                            SecureField("Private Key Passphrase", text: self.$draft.passphrase)
                        }
                    }
                    if self.draft.authKind == .password {
                        SecureField("Password", text: self.$draft.password)
                        Text("Password is stored in Keychain. The current stable transfer backend uses system SSH, so password-based file browsing is blocked until the native Swift backend graduates.")
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.68))
                    }
                }

                Section("Paths") {
                    TextField("Remote Default Path", text: self.$draft.remoteDefaultPath)
                    HStack {
                        TextField("Local Default Path", text: self.$draft.localDefaultPath)
                        Button("Choose...") {
                            self.chooseLocalFolder()
                        }
                    }
                }

                Section("Metadata") {
                    TextField("Tags", text: self.$draft.tags, prompt: Text("production, website"))
                    TextField("Notes", text: self.$draft.notes, axis: .vertical)
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
            .navigationTitle(self.savesAndConnects ? "New Connection" : (self.draft.displayName.isEmpty ? "New Server" : self.draft.displayName))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: self.onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(self.savesAndConnects ? "Save & Connect" : "Save", action: self.onSave)
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
