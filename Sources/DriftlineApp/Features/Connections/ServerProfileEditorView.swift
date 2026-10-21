import AppKit
import DriftlineCore
import SwiftUI

struct ServerProfileEditorView: View {
    @Binding var draft: ServerProfileDraft
    var savesAndConnects: Bool
    var errorMessage: String?
    var onCancel: () -> Void
    var onSave: () -> Void
    /// Probes the host (protocol, port, TLS, login methods) without logging in.
    var detect: (_ host: String, _ port: Int?, _ username: String) async -> ServerDetection? = { _, _, _ in nil }
    @State private var isDetecting = false
    @State private var detectionFailed = false

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
                                self.draft.protocolEdited = true
                                self.draft.portEdited = true
                            }
                        }
                        .task(id: self.draft.host) {
                            await self.detectAfterTyping()
                        }
                    self.detectionRow
                    Picker(LocalizationManager.shared.localized("profile.protocol"), selection: Binding(
                        get: { self.draft.protocolKind },
                        set: {
                            self.draft.changeProtocol(to: $0)
                            self.draft.protocolEdited = true
                        }
                    )) {
                        ForEach(TransferProtocolKind.allCases) { protocolKind in
                            Text(protocolKind.rawValue.uppercased()).tag(protocolKind)
                        }
                    }
                    TextField(LocalizationManager.shared.localized("profile.port"), value: Binding(
                        get: { self.draft.port },
                        set: {
                            self.draft.port = $0
                            self.draft.portEdited = true
                        }
                    ), format: .number.grouping(.never))
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
                    TextField(LocalizationManager.shared.localized("profile.username"), text: Binding(
                        get: { self.draft.username },
                        set: {
                            self.draft.username = $0
                            self.draft.usernameEdited = true
                        }
                    ))
                    Picker(LocalizationManager.shared.localized("profile.method"), selection: Binding(
                        get: { self.draft.authKind },
                        set: {
                            self.draft.authKind = $0
                            self.draft.authEdited = true
                        }
                    )) {
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

    @ViewBuilder
    private var detectionRow: some View {
        if self.isDetecting {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(LocalizationManager.shared.localized("detect.checking"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let detection = self.draft.detection {
            VStack(alignment: .leading, spacing: 6) {
                Label(Self.summary(of: detection), systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !self.draft.isNew, self.differs(from: detection) {
                    Button(LocalizationManager.shared.localized("detect.apply")) {
                        self.draft.apply(detection, force: true)
                    }
                    .controlSize(.small)
                }
            }
        } else if self.detectionFailed {
            Label(LocalizationManager.shared.localized("detect.none"), systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Waits until the user stops typing, then probes. A new profile takes the result for untouched fields.
    private func detectAfterTyping() async {
        let host = self.draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isDetecting = false
        guard host.count > 1, !host.contains("://"), ServerProfileValidator.isUsableHost(host) else {
            self.draft.detection = nil
            self.detectionFailed = false
            return
        }
        // The host also changes when an alias resolves: that host is already detected.
        guard self.draft.detection?.host != host else { return }
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !Task.isCancelled else { return }
        self.isDetecting = true
        defer { self.isDetecting = false }
        self.detectionFailed = false
        let port: Int? = self.draft.portEdited || self.draft.protocolEdited ? self.draft.port : nil
        let detection = await self.detect(host, port, self.draft.username)
        guard !Task.isCancelled, self.draft.host.trimmingCharacters(in: .whitespacesAndNewlines) == host else { return }
        guard let detection else {
            self.draft.detection = nil
            self.detectionFailed = true
            return
        }
        if self.draft.isNew {
            self.draft.apply(detection, force: false)
        } else {
            self.draft.detection = detection
        }
    }

    private func differs(from detection: ServerDetection) -> Bool {
        detection.protocolKind != self.draft.protocolKind || detection.port != self.draft.port
            || detection.suggestedAuthentication.map { ServerProfileDraft.authKind(for: $0) != self.draft.authKind } == true
    }

    static func summary(of detection: ServerDetection) -> String {
        let loc = LocalizationManager.shared
        var name = detection.protocolKind.rawValue.uppercased()
        if detection.protocolKind == .ftps, let implicitTLS = detection.implicitTLS {
            name += " · " + loc.localized(implicitTLS ? "profile.ftpsMode.implicit" : "profile.ftpsMode.explicit")
        }
        var parts = [String(format: loc.localized("detect.found"), name, detection.port)]
        if let authentication = detection.suggestedAuthentication {
            parts.append(String(format: loc.localized("detect.login"), ServerProfileDraft.authKind(for: authentication).localizedTitle))
        }
        if detection.nativeSSHSupported == false {
            parts.append(loc.localized("detect.systemSSH"))
        }
        if let software = detection.serverSoftware, !software.isEmpty {
            parts.append("(\(software.prefix(60)))")
        }
        return parts.joined(separator: " ")
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
