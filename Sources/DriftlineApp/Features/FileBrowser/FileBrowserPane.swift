import AppKit
import DriftlineCore
import SwiftUI

struct FileBrowserPane: View {
    var title: String
    var path: String
    var items: [FileItem]
    var source: FileSource
    @Binding var selectionIDs: Set<String>
    var onSelectionChange: ([FileItem]) -> Void
    var onOpen: (FileItem) -> Void
    var onNavigate: (String) -> Void
    var onParent: () -> Void
    var onRefresh: () -> Void
    var onCreateFolder: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void
    var onTransfer: ([FileItem]) -> Void
    var onDropItems: ([FileItem]) -> Bool
    var onCopy: ([FileItem]) -> Void
    var onPaste: () -> Void
    var onShowInfo: () -> Void
    var loadChildren: (FileItem, @escaping ([FileItem]) -> Void) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(self.title)
                    .font(.headline)
                Spacer()
                PaneToolbarButton(title: LocalizationManager.shared.localized("browser.upOneFolder"), systemImage: "chevron.up", action: self.onParent)
                PaneToolbarButton(title: String(format: LocalizationManager.shared.localized("browser.refreshPane"), self.title), systemImage: "arrow.clockwise", action: self.onRefresh)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(.regularMaterial)

            FileBrowserOutlineView(
                source: self.source,
                items: self.items,
                selectionIDs: self.$selectionIDs,
                onSelectionChange: self.onSelectionChange,
                onOpen: self.onOpen,
                onTransfer: self.onTransfer,
                onDropItems: self.onDropItems,
                onCopy: self.onCopy,
                onPaste: self.onPaste,
                onRename: self.onRename,
                onDelete: self.onDelete,
                onShowInfo: self.onShowInfo,
                loadChildren: self.loadChildren
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if self.items.isEmpty {
                    EmptyStateView(
                        title: self.title == LocalizationManager.shared.localized("browser.remote") ? LocalizationManager.shared.localized("browser.emptyRemote") : LocalizationManager.shared.localized("browser.emptyLocal"),
                        message: self.title == LocalizationManager.shared.localized("browser.remote") ? LocalizationManager.shared.localized("browser.emptyRemoteMessage") : LocalizationManager.shared.localized("browser.emptyLocalMessage"),
                        systemImage: self.title == LocalizationManager.shared.localized("browser.remote") ? "network.slash" : "folder"
                    )
                }
            }

            PathBreadcrumbBar(sourceTitle: self.title, path: self.path, onNavigate: self.onNavigate)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
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
                    .help(String(format: LocalizationManager.shared.localized("browser.goTo"), component.path))

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
    var id: String {
        self.path
    }

    var title: String
    var path: String
    var systemImage: String

    static func build(sourceTitle: String, path: String) -> [PathBreadcrumb] {
        if sourceTitle == LocalizationManager.shared.localized("browser.remote") {
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
            let title = index == 0 ? LocalizationManager.shared.localized("browser.macintoshHD") : component
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
