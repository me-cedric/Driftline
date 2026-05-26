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
                    TextField("Display Name", text: $draft.displayName)
                    TextField("Host", text: $draft.host)
                    Picker("Protocol", selection: $draft.protocolKind) {
                        ForEach(TransferProtocolKind.allCases) { protocolKind in
                            Text(protocolKind.rawValue.uppercased()).tag(protocolKind)
                        }
                    }
                    Stepper(value: $draft.port, in: 1...65_535) {
                        LabeledContent("Port", value: "\(draft.port)")
                    }
                    TextField("Group", text: $draft.groupName)
                    Toggle("Favorite", isOn: $draft.isFavorite)
                }

                Section("Authentication") {
                    TextField("Username", text: $draft.username)
                    Picker("Method", selection: $draft.authKind) {
                        ForEach(ServerProfileDraft.AuthKind.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    if draft.authKind == .privateKey {
                        HStack {
                            TextField("Private Key Path", text: $draft.privateKeyPath)
                            Button("Choose...") {
                                choosePrivateKey()
                            }
                        }
                        Toggle("Store passphrase in Keychain", isOn: $draft.storePassphrase)
                        if draft.storePassphrase {
                            SecureField("Private Key Passphrase", text: $draft.passphrase)
                        }
                    }
                    if draft.authKind == .password {
                        SecureField("Password", text: $draft.password)
                        Text("Password is stored in Keychain. The current stable transfer backend uses system SSH, so password-based file browsing is blocked until the native Swift backend graduates.")
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.68))
                    }
                }

                Section("Paths") {
                    TextField("Remote Default Path", text: $draft.remoteDefaultPath)
                    HStack {
                        TextField("Local Default Path", text: $draft.localDefaultPath)
                        Button("Choose...") {
                            chooseLocalFolder()
                        }
                    }
                }

                Section("Metadata") {
                    TextField("Tags", text: $draft.tags, prompt: Text("production, website"))
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(savesAndConnects ? "New Connection" : (draft.displayName.isEmpty ? "New Server" : draft.displayName))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(savesAndConnects ? "Save & Connect" : "Save", action: onSave)
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
            draft.privateKeyPath = url.path
        }
    }

    private func chooseLocalFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: NSString(string: draft.localDefaultPath).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            draft.localDefaultPath = url.path
        }
    }
}
