import AppKit
import DriftlineCore
import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserPane: View {
    var title: String
    var path: String
    var items: [FileItem]
    @Binding var selection: FileItem?
    var onOpen: (FileItem) -> Void
    var onNavigate: (String) -> Void
    var onParent: () -> Void
    var onRefresh: () -> Void
    var onCreateFolder: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void
    var onTransfer: (FileItem) -> Void
    var onDropItems: ([String]) -> Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(self.title)
                    .font(.headline)
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
                    HStack(spacing: 8) {
                        FileItemIcon(item: item)
                            .frame(width: 18, height: 18)
                        Text(item.name)
                            .lineLimit(1)
                    }
                        .accessibilityLabel("\(item.name), \(item.kind.rawValue)")
                }
                .width(min: 170, ideal: 260)
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
            .contextMenu(forSelectionType: String.self) { ids in
                if let item = self.contextItem(for: ids) {
                    Button(self.title == "Local" ? "Upload" : "Download") {
                        self.selection = item
                        self.onTransfer(item)
                    }
                    Divider()
                }
                Button("New Folder", action: self.onCreateFolder)
                Divider()
                Button("Copy Path") {
                    if let item = self.contextItem(for: ids) {
                        self.copyPath(item.path)
                    }
                }
                Button(self.title == "Local" ? "Reveal in Finder" : "Copy Remote Path") {
                    guard let item = self.contextItem(for: ids) else { return }
                    if self.title == "Local" {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                    } else {
                        self.copyPath(item.path)
                    }
                }
                Divider()
                Button("Rename") {
                    if let item = self.contextItem(for: ids) {
                        self.selection = item
                    }
                    self.onRename()
                }
                Button("Delete", role: .destructive) {
                    if let item = self.contextItem(for: ids) {
                        self.selection = item
                    }
                    self.onDelete()
                }
            } primaryAction: { ids in
                if let item = self.items.first(where: { ids.contains($0.id) }) {
                    self.selection = item
                    if item.kind == .folder {
                        self.onOpen(item)
                    } else {
                        self.onTransfer(item)
                    }
                }
            }
            .dropDestination(for: String.self) { ids, _ in
                self.onDropItems(ids)
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

            PathBreadcrumbBar(sourceTitle: self.title, path: self.path, onNavigate: self.onNavigate)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func contextItem(for ids: Set<String>) -> FileItem? {
        if let item = self.items.first(where: { ids.contains($0.id) }) {
            return item
        }
        return self.selection
    }

    private func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}

private struct FileItemIcon: View {
    var item: FileItem

    var body: some View {
        Image(nsImage: self.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private var icon: NSImage {
        if item.source == .local {
            return NSWorkspace.shared.icon(forFile: item.path)
        }
        return NSWorkspace.shared.icon(for: self.remoteContentType)
    }

    private var remoteContentType: UTType {
        switch item.kind {
        case .folder:
            return UTType.folder
        case .symbolicLink:
            return UTType.aliasFile
        case .unknown:
            return UTType.data
        case .file:
            guard let fileExtension = item.name.split(separator: ".").last.map(String.init),
                  fileExtension != item.name,
                  let contentType = UTType(filenameExtension: fileExtension)
            else {
                return UTType.data
            }
            return contentType
        }
    }
}

private struct PathBreadcrumbBar: View {
    var sourceTitle: String
    var path: String
    var onNavigate: (String) -> Void

    private var components: [PathBreadcrumb] {
        PathBreadcrumb.build(sourceTitle: self.sourceTitle, path: self.path)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(self.components) { component in
                    Button {
                        self.onNavigate(component.path)
                    } label: {
                        Label(component.title, systemImage: component.systemImage)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help("Go to \(component.path)")

                    if component.id != self.components.last?.id {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }
}

private struct PathBreadcrumb: Identifiable {
    var id: String { self.path }
    var title: String
    var path: String
    var systemImage: String

    static func build(sourceTitle: String, path: String) -> [PathBreadcrumb] {
        if sourceTitle == "Remote" {
            return self.remote(path: path)
        }
        return self.local(path: path)
    }

    private static func local(path: String) -> [PathBreadcrumb] {
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents
        var breadcrumbs: [PathBreadcrumb] = []
        for index in components.indices {
            let component = components[index]
            let currentPath = NSString.path(withComponents: Array(components[...index]))
            let title = index == 0 ? "Macintosh HD" : component
            let icon = index == 0 ? "internaldrive" : "folder"
            breadcrumbs.append(PathBreadcrumb(title: title, path: currentPath, systemImage: icon))
        }
        return breadcrumbs
    }

    private static func remote(path: String) -> [PathBreadcrumb] {
        let normalized = path.isEmpty ? "/" : path
        let parts = normalized.split(separator: "/").map(String.init)
        var breadcrumbs = [PathBreadcrumb(title: "/", path: "/", systemImage: "network")]
        var current = ""
        for part in parts {
            current += "/\(part)"
            breadcrumbs.append(PathBreadcrumb(title: part, path: current, systemImage: "folder"))
        }
        return breadcrumbs
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
