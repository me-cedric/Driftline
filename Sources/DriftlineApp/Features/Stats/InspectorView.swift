import DriftlineCore
import SwiftUI

struct InspectorView: View {
    var file: FileItem?
    var session: ConnectionSession
    var profile: ServerProfile?
    var transferStats: TransferStats
    var lastConnection: String
    var onConnect: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(LocalizationManager.shared.localized("browser.inspector"))
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Image(systemName: "pin")
                            .foregroundStyle(.secondary)
                    }

                    InspectorSection(title: LocalizationManager.shared.localized("inspector.selection")) {
                        if let file {
                            self.fileSummary(file)
                            Divider()
                            self.inspectorRow(LocalizationManager.shared.localized("inspector.path"), value: file.path)
                            self.inspectorRow(LocalizationManager.shared.localized("inspector.type"), value: file.kind.localizedTitle)
                            self.inspectorRow(LocalizationManager.shared.localized("inspector.size"), value: file.size.map(ByteCountFormatter.string) ?? "--")
                            if let modifiedAt = file.modifiedAt {
                                self.inspectorRow(LocalizationManager.shared.localized("browser.column.modified"), value: Self.modifiedFormatter.string(from: modifiedAt))
                            }
                            if let permissions = file.permissions {
                                self.inspectorRow(LocalizationManager.shared.localized("inspector.permissions"), value: permissions)
                            }
                            Divider()
                            self.fileActions(file)
                        } else {
                            self.emptySelection
                        }
                    }

                    InspectorSection(title: LocalizationManager.shared.localized("inspector.connection")) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(self.stateColor)
                                .frame(width: 8, height: 8)
                            Text(self.session.state.localizedTitle)
                                .fontWeight(.medium)
                            Spacer()
                            Text(self.session.protocolKind?.rawValue.uppercased() ?? "--")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        self.inspectorRow(LocalizationManager.shared.localized("inspector.localPath"), value: self.session.localPath)
                        self.inspectorRow(LocalizationManager.shared.localized("inspector.remotePath"), value: self.session.remotePath)
                        if self.session.state == .disconnected {
                            Button(LocalizationManager.shared.localized("browser.connectToServer"), action: self.onConnect)
                                .buttonStyle(GlassButtonStyle(isPrimary: true))
                        }
                    }

                    InspectorSection(title: LocalizationManager.shared.localized("inspector.server")) {
                        if let profile {
                            self.inspectorRow(LocalizationManager.shared.localized("inspector.name"), value: profile.displayName)
                            self.inspectorRow(LocalizationManager.shared.localized("inspector.protocol"), value: profile.protocolKind.rawValue.uppercased())
                            self.inspectorRow(LocalizationManager.shared.localized("profile.host"), value: profile.host)
                            self.inspectorRow(LocalizationManager.shared.localized("profile.port"), value: "\(profile.port)")
                            self.inspectorRow(LocalizationManager.shared.localized("connection.favorite"), value: profile.isFavorite ? LocalizationManager.shared.localized("common.yes") : LocalizationManager.shared.localized("common.no"))
                        } else {
                            Text(LocalizationManager.shared.localized("inspector.noServerSelected"))
                                .font(.callout.weight(.medium))
                            Text(LocalizationManager.shared.localized("inspector.chooseServer"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    InspectorSection(title: LocalizationManager.shared.localized("inspector.activity")) {
                        self.inspectorRow(LocalizationManager.shared.localized("stats.lastConnection"), value: self.lastConnection)
                        self.inspectorRow(LocalizationManager.shared.localized("inspector.lastActivity"), value: self.session.connectedAt.map(Self.modifiedFormatter.string) ?? LocalizationManager.shared.localized("common.none"))
                        self.inspectorRow(LocalizationManager.shared.localized("transfer.transfers"), value: "\(self.transferStats.uploadCount + self.transferStats.downloadCount)")
                    }
                }
                .frame(width: max(0, proxy.size.width - 32), alignment: .topLeading)
                .padding(16)
            }
        }
    }

    private var emptySelection: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizationManager.shared.localized("inspector.noItemSelected"))
                    .font(.callout.weight(.semibold))
                Text(LocalizationManager.shared.localized("inspector.selectItem"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stateColor: Color {
        switch self.session.state {
        case .connected:
            .green
        case .connecting, .reconnecting:
            .blue
        case .failed:
            .red
        case .cancelling:
            .orange
        case .disconnected:
            .secondary
        }
    }

    private func fileSummary(_ file: FileItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: self.iconName(for: file.kind))
                .font(.title3)
                .foregroundStyle(file.source == .remote ? .blue : .primary)
                .frame(width: 34, height: 34)
                .background(.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                Text("\(file.source.localizedTitle) · \(file.kind.localizedTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func inspectorRow(_ title: String, value: String) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .truncationMode(.middle)
        } label: {
            Text(title)
        }
    }

    private func fileActions(_ file: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizationManager.shared.localized("inspector.actions"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if file.source == .local {
                self.actionGrid([
                    (LocalizationManager.shared.localized("inspector.quickLook"), "eye"),
                    (LocalizationManager.shared.localized("browser.upload"), "arrow.up.circle"),
                    (LocalizationManager.shared.localized("browser.revealFinder"), "magnifyingglass"),
                    (LocalizationManager.shared.localized("browser.copyPath"), "doc.on.doc"),
                ])
            } else {
                self.actionGrid([
                    (LocalizationManager.shared.localized("browser.download"), "arrow.down.circle"),
                    (LocalizationManager.shared.localized("browser.rename"), "pencil"),
                    (LocalizationManager.shared.localized("browser.delete"), "trash"),
                    (LocalizationManager.shared.localized("inspector.copyRemotePath"), "doc.on.doc"),
                ])
            }
        }
    }

    private func actionGrid(_ actions: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(actions, id: \.0) { action in
                Label(action.0, systemImage: action.1)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DriftlineRadius.control, style: .continuous))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func iconName(for kind: FileItemKind) -> String {
        switch kind {
        case .folder:
            "folder"
        case .symbolicLink:
            "link"
        case .file:
            "doc"
        case .unknown:
            "questionmark.square"
        }
    }

    private static let modifiedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
