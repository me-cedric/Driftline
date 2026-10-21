import AppKit
import DriftlineCore
import SwiftUI

struct FileBrowserPane: View {
    var title: String
    var path: String
    var items: [FileItem]
    var source: FileSource
    var isConnected = true
    @Binding var filterText: String
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
    var onNewConnection: (() -> Void)?
    var loadChildren: (FileItem, @escaping ([FileItem]) -> Void) -> Void

    private var filteredItems: [FileItem] {
        let query = self.filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return self.items }
        return self.items.filter { item in
            item.name.localizedCaseInsensitiveContains(query)
                || item.path.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            self.header
            Divider()
            self.browserBody
            Divider()
            self.footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: self.path) { _, _ in
            // A filter belongs to one folder; Finder also clears its search when you open another one.
            self.filterText = ""
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                // Title and pane actions share one row, like a Finder window header.
                HStack(spacing: 10) {
                    Label(self.title, systemImage: self.source == .local ? "desktopcomputer" : "server.rack")
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        PaneToolbarButton(title: LocalizationManager.shared.localized("browser.upOneFolder"), systemImage: "chevron.up", isDisabled: self.source == .remote && !self.isConnected, action: self.onParent)
                        PaneToolbarButton(title: LocalizationManager.shared.localized("browser.newFolder"), systemImage: "folder.badge.plus", isDisabled: self.source == .remote && !self.isConnected, action: self.onCreateFolder)
                        PaneToolbarButton(title: String(format: LocalizationManager.shared.localized("browser.refreshPane"), self.title), systemImage: "arrow.clockwise", isDisabled: self.source == .remote && !self.isConnected, action: self.onRefresh)
                        PaneToolbarButton(title: LocalizationManager.shared.localized("connection.more"), systemImage: "ellipsis", action: self.onShowInfo)
                    }
                    .driftlineGlassGroup()
                }

                // The breadcrumb bar below shows the path; this line only explains a disconnected pane.
                if self.source == .remote, !self.isConnected {
                    Text(self.headerSubtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            PathBreadcrumbBar(sourceTitle: self.title, path: self.path, onNavigate: self.onNavigate)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 13)
    }

    private var browserBody: some View {
        // Connecting swaps the prompt for the files with a cross-fade.
        ZStack {
            if self.source == .remote, !self.isConnected {
                RemoteEmptyStateView(onNewConnection: self.onNewConnection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                self.fileTable
                    .transition(.opacity)
            }
        }
        .driftlineAnimation(value: self.isConnected)
    }

    private var fileTable: some View {
        FileBrowserOutlineView(
            source: self.source,
            items: self.filteredItems,
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
                    title: self.source == .remote ? LocalizationManager.shared.localized("browser.emptyRemote") : LocalizationManager.shared.localized("browser.emptyLocal"),
                    message: self.source == .remote ? LocalizationManager.shared.localized("browser.emptyRemoteMessage") : LocalizationManager.shared.localized("browser.emptyLocalMessage"),
                    systemImage: self.source == .remote ? "network.slash" : "folder"
                )
            } else if self.filteredItems.isEmpty {
                EmptyStateView(
                    title: LocalizationManager.shared.localized("browser.noFilterResults"),
                    message: LocalizationManager.shared.localized("browser.noFilterResultsMessage"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: self.source == .local ? "internaldrive" : (self.isConnected ? "network" : "icloud.slash"))
                .foregroundStyle(.secondary)
            Text(self.footerStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(String(format: LocalizationManager.shared.localized("browser.itemCount"), self.filteredItems.count))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var headerSubtitle: String {
        if self.source == .remote, !self.isConnected {
            return "\(LocalizationManager.shared.localized("connection.disconnected")) / \(LocalizationManager.shared.localized("alert.notConnectedTitle"))"
        }
        return self.pathDisplay
    }

    private var footerStatus: String {
        if self.source == .remote, !self.isConnected {
            return LocalizationManager.shared.localized("connection.disconnected")
        }
        return self.source.localizedTitle
    }

    private var pathDisplay: String {
        PathBreadcrumb.build(sourceTitle: self.title, path: self.path)
            .map(\.title)
            .joined(separator: " › ")
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(String(format: LocalizationManager.shared.localized("browser.goTo"), component.path))

                    if component.id != self.components.last?.id {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
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
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .driftlineGlassButton()
        .buttonBorderShape(.circle)
        .disabled(self.isDisabled)
        .help(self.title)
        .accessibilityLabel(self.title)
    }
}

private struct RemoteEmptyStateView: View {
    var onNewConnection: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.9))
                .frame(width: 64, height: 64)
                .background(.quaternary, in: Circle())
            VStack(spacing: 6) {
                Text(LocalizationManager.shared.localized("browser.noRemoteConnection"))
                    .font(.title3.weight(.semibold))
                Text(LocalizationManager.shared.localized("browser.noRemoteConnectionMessage"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360)
            if let onNewConnection {
                // A lone call to action: large and capsule-shaped, like the system empty states.
                Button(LocalizationManager.shared.localized("sidebar.newConnection"), action: onNewConnection)
                    .driftlineGlassButton(prominent: true)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ByteCountFormatter {
    static func string(fromByteCount byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }
}
