import DriftlineCore
import SwiftUI

struct FileBrowserPane: View {
    var title: String
    var path: String
    var items: [FileItem]
    @Binding var selection: FileItem?
    var onOpen: (FileItem) -> Void
    var onParent: () -> Void
    var onRefresh: () -> Void
    var onCreateFolder: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.title)
                        .font(.headline)
                    Text(self.path)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.68))
                        .lineLimit(1)
                }
                Spacer()
                PaneToolbarButton(title: "Up One Folder", systemImage: "chevron.up", action: self.onParent)
                PaneToolbarButton(title: "Refresh \(self.title)", systemImage: "arrow.clockwise", action: self.onRefresh)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(.regularMaterial)

            Table(self.items, selection: Binding(get: {
                self.selection?.id
            }, set: { id in
                self.selection = self.items.first { $0.id == id }
            })) {
                TableColumn("Name") { item in
                    Label(item.name, systemImage: item.kind == .folder ? "folder" : "doc")
                        .accessibilityLabel("\(item.name), \(item.kind.rawValue)")
                }
                .width(min: 140, ideal: 220)
                TableColumn("Size") { item in
                    Text(item.size.map(ByteCountFormatter.string) ?? "--")
                        .foregroundStyle(.primary.opacity(0.72))
                }
                .width(min: 72, ideal: 90, max: 120)
                TableColumn("Type") { item in
                    Text(item.kind.rawValue.capitalized)
                        .foregroundStyle(.primary.opacity(0.72))
                }
                .width(min: 72, ideal: 90, max: 120)
                TableColumn("Modified") { item in
                    Text(item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "--")
                        .foregroundStyle(.primary.opacity(0.72))
                }
                .width(min: 112, ideal: 190)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contextMenu(forSelectionType: String.self) { _ in
                Button("New Folder", action: self.onCreateFolder)
                Divider()
                Button("Copy Path") {
                    if let selection {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(selection.path, forType: .string)
                    }
                }
                Button(self.title == "Local" ? "Reveal in Finder" : "Copy Remote Path") {
                    guard let selection else { return }
                    if self.title == "Local" {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: selection.path)])
                    } else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(selection.path, forType: .string)
                    }
                }
                Divider()
                Button("Rename", action: self.onRename)
                Button("Delete", role: .destructive, action: self.onDelete)
            } primaryAction: { ids in
                selection = self.items.first { ids.contains($0.id) }
                if let selection {
                    self.onOpen(selection)
                }
            }
            .overlay {
                if self.items.isEmpty {
                    EmptyStateView(
                        title: self.title == "Remote" ? "No Remote Listing" : "This Folder Is Empty",
                        message: self.title == "Remote" ? "Create a connection, select a saved server, then press Connect." : "Create a folder or choose another local path.",
                        systemImage: self.title == "Remote" ? "network.slash" : "folder"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

private struct PaneToolbarButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 20)
                .contentShape(Rectangle())
        }
        .help(self.title)
        .accessibilityLabel(self.title)
    }
}

extension ByteCountFormatter {
    static func string(fromByteCount byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }
}
