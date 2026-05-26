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
                    Text(title)
                        .font(.headline)
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.68))
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onParent) { Image(systemName: "chevron.up") }
                    .help("Parent Folder")
                    .accessibilityLabel("Parent Folder")
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
                    .accessibilityLabel("Refresh \(title)")
            }
            .padding(12)
            .background(.regularMaterial)

            Table(items, selection: Binding(get: {
                selection?.id
            }, set: { id in
                selection = items.first { $0.id == id }
            })) {
                TableColumn("Name") { item in
                    Label(item.name, systemImage: item.kind == .folder ? "folder" : "doc")
                        .accessibilityLabel("\(item.name), \(item.kind.rawValue)")
                }
                TableColumn("Size") { item in
                    Text(item.size.map(ByteCountFormatter.string) ?? "--")
                        .foregroundStyle(.primary.opacity(0.72))
                }
                TableColumn("Type") { item in
                    Text(item.kind.rawValue.capitalized)
                        .foregroundStyle(.primary.opacity(0.72))
                }
                TableColumn("Modified") { item in
                    Text(item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "--")
                        .foregroundStyle(.primary.opacity(0.72))
                }
            }
            .contextMenu(forSelectionType: String.self) { _ in
                Button("New Folder", action: onCreateFolder)
                Divider()
                Button("Copy Path") {
                    if let selection {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(selection.path, forType: .string)
                    }
                }
                Button(title == "Local" ? "Reveal in Finder" : "Copy Remote Path") {
                    guard let selection else { return }
                    if title == "Local" {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: selection.path)])
                    } else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(selection.path, forType: .string)
                    }
                }
                Divider()
                Button("Rename", action: onRename)
                Button("Delete", role: .destructive, action: onDelete)
            } primaryAction: { ids in
                selection = items.first { ids.contains($0.id) }
                if let selection {
                    onOpen(selection)
                }
            }
            .overlay {
                if items.isEmpty {
                    EmptyStateView(
                        title: title == "Remote" ? "No Remote Listing" : "This Folder Is Empty",
                        message: title == "Remote" ? "Create a connection, select a saved server, then press Connect." : "Create a folder or choose another local path.",
                        systemImage: title == "Remote" ? "network.slash" : "folder"
                    )
                }
            }
        }
        .background(.ultraThinMaterial)
    }
}

extension ByteCountFormatter {
    static func string(fromByteCount byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }
}
