import AppKit
import DriftlineCore
import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserOutlineView: NSViewRepresentable {
    var source: FileSource
    var items: [FileItem]
    @Binding var selectionIDs: Set<String>
    var onSelectionChange: ([FileItem]) -> Void
    var onOpen: (FileItem) -> Void
    var onTransfer: ([FileItem]) -> Void
    var onDropItems: ([FileItem]) -> Bool
    var onCopy: ([FileItem]) -> Void
    var onPaste: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void
    var onShowInfo: () -> Void
    var loadChildren: (FileItem, @escaping ([FileItem]) -> Void) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let outlineView = FileBrowserNativeOutlineView()
        outlineView.setAccessibilityLabel(String(format: LocalizationManager.shared.localized("browser.fileBrowser"), self.source.localizedTitle))
        outlineView.headerView = NSTableHeaderView()
        outlineView.rowSizeStyle = .custom
        outlineView.rowHeight = 28
        outlineView.intercellSpacing = NSSize(width: 0, height: 3)
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.backgroundColor = .clear
        outlineView.selectionHighlightStyle = .none
        outlineView.gridStyleMask = []
        outlineView.allowsMultipleSelection = true
        outlineView.allowsEmptySelection = true
        outlineView.allowsColumnSelection = false
        outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outlineView.registerForDraggedTypes([Coordinator.fileItemPasteboardType, Coordinator.itemIDPasteboardType, .string])
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        outlineView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        outlineView.target = context.coordinator
        outlineView.actionHandler = context.coordinator

        let nameColumn = self.makeColumn("name", title: LocalizationManager.shared.localized("browser.column.name"), width: 260)
        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn
        outlineView.addTableColumn(self.makeColumn("size", title: LocalizationManager.shared.localized("browser.column.size"), width: 90))
        outlineView.addTableColumn(self.makeColumn("type", title: LocalizationManager.shared.localized("browser.column.type"), width: 110))
        outlineView.addTableColumn(self.makeColumn("modified", title: LocalizationManager.shared.localized("browser.column.modified"), width: 170))

        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator

        scrollView.documentView = outlineView
        context.coordinator.outlineView = outlineView
        context.coordinator.replaceRootItems(self.items)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.replaceRootItems(self.items)
        guard let outlineView = scrollView.documentView as? NSOutlineView else { return }
        context.coordinator.applySelection(to: outlineView)
    }

    private func makeColumn(_ id: String, title: String, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.minWidth = id == "name" ? 180 : 70
        column.width = width
        column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        return column
    }
}

extension FileBrowserOutlineView {
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let itemIDPasteboardType = NSPasteboard.PasteboardType("app.driftline.file-item-id")
        static let fileItemPasteboardType = NSPasteboard.PasteboardType("app.driftline.file-item")

        var parent: FileBrowserOutlineView
        weak var outlineView: NSOutlineView?
        private var rootNodes: [FileBrowserNode] = []
        private var nodeByID: [String: FileBrowserNode] = [:]
        private var rootSignature: [String] = []
        private var isApplyingSelection = false
        private var sortColumn = "name"
        private var sortAscending = true

        init(_ parent: FileBrowserOutlineView) {
            self.parent = parent
        }

        func replaceRootItems(_ items: [FileItem]) {
            let newSignature = items.map(self.signature(for:))
            guard newSignature != self.rootSignature else { return }
            self.rootSignature = newSignature
            let expandedIDs = self.expandedIDs()
            self.rootNodes = items.map { item in
                let node = self.nodeByID[item.id] ?? FileBrowserNode(item: item)
                node.item = item
                return node
            }
            self.rebuildIndex()
            self.sortAllNodes()
            self.outlineView?.reloadData()
            self.restoreExpandedIDs(expandedIDs)
        }

        func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? FileBrowserNode else {
                return self.rootNodes.count
            }
            if node.isPlaceholder { return 0 }
            if node.item.kind == .folder, !node.loaded {
                return 1
            }
            return node.children.count
        }

        func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? FileBrowserNode else {
                return self.rootNodes[index]
            }
            if node.item.kind == .folder, !node.loaded {
                return FileBrowserNode.placeholder(parentID: node.id)
            }
            return node.children[index]
        }

        func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? FileBrowserNode else { return false }
            return !node.isPlaceholder && node.item.kind == .folder
        }

        func outlineView(_: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileBrowserNode else { return nil }
            let columnID = tableColumn?.identifier.rawValue ?? "name"
            if columnID == "name" {
                let cell = FileBrowserNameCellView()
                cell.configure(node: node, source: self.parent.source)
                return cell
            }
            let cell = NSTableCellView()
            let textField = NSTextField(labelWithString: self.value(for: columnID, node: node))
            textField.setAccessibilityLabel(String(format: LocalizationManager.shared.localized("browser.column.accessibility"), self.localizedColumnTitle(for: columnID), textField.stringValue))
            textField.lineBreakMode = .byTruncatingMiddle
            textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            textField.textColor = .secondaryLabelColor
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        func outlineView(_: NSOutlineView, rowViewForItem _: Any) -> NSTableRowView? {
            FileBrowserRowView()
        }

        func outlineViewItemWillExpand(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView,
                  let node = notification.userInfo?["NSObject"] as? FileBrowserNode,
                  node.item.kind == .folder,
                  !node.loaded,
                  !node.loading
            else { return }

            node.loading = true
            self.parent.loadChildren(node.item) { [weak self, weak outlineView, weak node] children in
                guard let self, let outlineView, let node else { return }
                node.loading = false
                node.loaded = true
                node.children = children.map { FileBrowserNode(item: $0) }
                self.rebuildIndex()
                self.sortAllNodes()
                outlineView.reloadItem(node, reloadChildren: true)
                outlineView.expandItem(node)
            }
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !self.isApplyingSelection,
                  let outlineView = notification.object as? NSOutlineView
            else { return }
            let selected = outlineView.selectedRowIndexes.compactMap { row -> FileItem? in
                guard let node = outlineView.item(atRow: row) as? FileBrowserNode,
                      !node.isPlaceholder
                else { return nil }
                return node.item
            }
            self.parent.selectionIDs = Set(selected.map(\.id))
            self.parent.onSelectionChange(selected)
        }

        func outlineView(_: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = self.outlineView?.sortDescriptors.first ?? oldDescriptors.first else { return }
            self.sortColumn = descriptor.key ?? "name"
            self.sortAscending = descriptor.ascending
            self.sortAllNodes()
            self.outlineView?.reloadData()
            if let outlineView {
                self.applySelection(to: outlineView)
            }
        }

        func outlineView(_: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let node = item as? FileBrowserNode, !node.isPlaceholder else { return nil }
            let pasteboardItem = NSPasteboardItem()
            if let data = try? JSONEncoder().encode(node.item) {
                pasteboardItem.setData(data, forType: Self.fileItemPasteboardType)
            }
            pasteboardItem.setString(node.item.id, forType: Self.itemIDPasteboardType)
            pasteboardItem.setString(node.item.id, forType: .string)
            return pasteboardItem
        }

        func outlineView(_: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem _: Any?, proposedChildIndex _: Int) -> NSDragOperation {
            self.draggedItems(from: info).isEmpty ? [] : .copy
        }

        func outlineView(_: NSOutlineView, acceptDrop info: NSDraggingInfo, item _: Any?, childIndex _: Int) -> Bool {
            let items = self.draggedItems(from: info)
            guard !items.isEmpty else { return false }
            return self.parent.onDropItems(items)
        }

        @objc func doubleClicked(_ sender: NSOutlineView) {
            let selectedItems = sender.selectedRowIndexes.compactMap { row -> FileItem? in
                guard let node = sender.item(atRow: row) as? FileBrowserNode, !node.isPlaceholder else { return nil }
                return node.item
            }
            if selectedItems.count > 1 {
                self.parent.onTransfer(selectedItems)
                return
            }
            guard let item = selectedItems.first else { return }
            if item.kind == .folder {
                self.parent.onOpen(item)
            } else {
                self.parent.onTransfer([item])
            }
        }

        func selectedItems() -> [FileItem] {
            guard let outlineView else { return [] }
            return outlineView.selectedRowIndexes.compactMap { row -> FileItem? in
                guard let node = outlineView.item(atRow: row) as? FileBrowserNode,
                      !node.isPlaceholder
                else { return nil }
                return node.item
            }
        }

        func copySelectedItems() {
            let items = self.selectedItems()
            guard !items.isEmpty else { return }
            self.parent.onCopy(items)
        }

        func transferSelectedItems() {
            let items = self.selectedItems()
            guard !items.isEmpty else { return }
            self.parent.onTransfer(items)
        }

        func pasteItems() {
            self.parent.onPaste()
        }

        func renameSelectedItem() {
            guard self.selectedItems().count == 1 else { return }
            self.parent.onRename()
        }

        func deleteSelectedItems() {
            guard !self.selectedItems().isEmpty else { return }
            self.parent.onDelete()
        }

        func showSelectedInfo() {
            guard !self.selectedItems().isEmpty else { return }
            self.parent.onShowInfo()
        }

        func contextMenu() -> NSMenu {
            let items = self.selectedItems()
            let menu = NSMenu()

            let transferTitle = self.parent.source == .local ? LocalizationManager.shared.localized("browser.upload") : LocalizationManager.shared.localized("browser.download")
            menu.addItem(self.menuItem(transferTitle, action: #selector(self.transferMenuItem(_:)), enabled: !items.isEmpty))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(self.menuItem(LocalizationManager.shared.localized("menu.copy"), action: #selector(self.copyMenuItem(_:)), keyEquivalent: "c", enabled: !items.isEmpty))
            menu.addItem(self.menuItem(LocalizationManager.shared.localized("menu.paste"), action: #selector(self.pasteMenuItem(_:)), keyEquivalent: "v", enabled: true))
            menu.addItem(self.menuItem(LocalizationManager.shared.localized("browser.copyPath"), action: #selector(self.copyPathMenuItem(_:)), enabled: !items.isEmpty))
            if self.parent.source == .local {
                menu.addItem(self.menuItem(LocalizationManager.shared.localized("browser.revealFinder"), action: #selector(self.revealMenuItem(_:)), enabled: !items.isEmpty))
            }
            menu.addItem(NSMenuItem.separator())
            menu.addItem(self.menuItem(LocalizationManager.shared.localized("browser.getInfo"), action: #selector(self.infoMenuItem(_:)), enabled: !items.isEmpty))
            menu.addItem(self.menuItem(LocalizationManager.shared.localized("browser.rename"), action: #selector(self.renameMenuItem(_:)), enabled: items.count == 1))
            menu.addItem(self.menuItem(LocalizationManager.shared.localized("browser.delete"), action: #selector(self.deleteMenuItem(_:)), enabled: !items.isEmpty))
            return menu
        }

        @objc private func transferMenuItem(_: NSMenuItem) {
            let items = self.selectedItems()
            guard !items.isEmpty else { return }
            self.parent.onTransfer(items)
        }

        @objc private func copyMenuItem(_: NSMenuItem) {
            self.copySelectedItems()
        }

        @objc private func pasteMenuItem(_: NSMenuItem) {
            self.pasteItems()
        }

        @objc private func copyPathMenuItem(_: NSMenuItem) {
            let paths = self.selectedItems().map(\.path)
            guard !paths.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        }

        @objc private func revealMenuItem(_: NSMenuItem) {
            let urls = self.selectedItems()
                .filter { $0.source == .local }
                .map { URL(fileURLWithPath: $0.path) }
            guard !urls.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }

        @objc private func infoMenuItem(_: NSMenuItem) {
            self.parent.onShowInfo()
        }

        @objc private func renameMenuItem(_: NSMenuItem) {
            self.parent.onRename()
        }

        @objc private func deleteMenuItem(_: NSMenuItem) {
            self.parent.onDelete()
        }

        func applySelection(to outlineView: NSOutlineView) {
            self.isApplyingSelection = true
            defer { self.isApplyingSelection = false }
            let rows = NSMutableIndexSet()
            for row in 0 ..< outlineView.numberOfRows {
                guard let node = outlineView.item(atRow: row) as? FileBrowserNode,
                      !node.isPlaceholder,
                      self.parent.selectionIDs.contains(node.item.id)
                else { continue }
                rows.add(row)
            }
            outlineView.selectRowIndexes(rows as IndexSet, byExtendingSelection: false)
        }

        private func value(for columnID: String, node: FileBrowserNode) -> String {
            guard !node.isPlaceholder else { return "" }
            switch columnID {
            case "size":
                return node.item.kind == .folder ? "--" : node.item.size.map(ByteCountFormatter.string) ?? "--"
            case "type":
                return node.item.kind.localizedTitle
            case "modified":
                return node.item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "--"
            default:
                return node.item.name
            }
        }

        private func menuItem(_ title: String, action: Selector, keyEquivalent: String = "", enabled: Bool) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
            item.target = self
            item.isEnabled = enabled
            return item
        }

        private func draggedItems(from info: NSDraggingInfo) -> [FileItem] {
            let pasteboardItems = info.draggingPasteboard.pasteboardItems ?? []
            return pasteboardItems.compactMap { item in
                guard let data = item.data(forType: Self.fileItemPasteboardType) else { return nil }
                return try? JSONDecoder().decode(FileItem.self, from: data)
            }
        }

        private func rebuildIndex() {
            self.nodeByID = [:]
            func index(_ node: FileBrowserNode) {
                guard !node.isPlaceholder else { return }
                self.nodeByID[node.id] = node
                node.children.forEach(index)
            }
            self.rootNodes.forEach(index)
        }

        private func signature(for item: FileItem) -> String {
            "\(item.id)|\(item.kind.rawValue)|\(item.size ?? -1)|\(item.modifiedAt?.timeIntervalSince1970 ?? -1)"
        }

        private func sortAllNodes() {
            func sort(_ nodes: inout [FileBrowserNode]) {
                nodes.sort { lhs, rhs in
                    self.compare(lhs.item, rhs.item)
                }
                for node in nodes {
                    sort(&node.children)
                }
            }
            sort(&self.rootNodes)
        }

        private func compare(_ lhs: FileItem, _ rhs: FileItem) -> Bool {
            if lhs.kind != rhs.kind {
                if lhs.kind == .folder { return true }
                if rhs.kind == .folder { return false }
            }
            let orderedAscending: Bool = switch self.sortColumn {
            case "size":
                (lhs.size ?? -1) < (rhs.size ?? -1)
            case "type":
                lhs.kind.rawValue.localizedCaseInsensitiveCompare(rhs.kind.rawValue) == .orderedAscending
            case "modified":
                (lhs.modifiedAt ?? .distantPast) < (rhs.modifiedAt ?? .distantPast)
            default:
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return self.sortAscending ? orderedAscending : !orderedAscending
        }

        private func localizedColumnTitle(for columnID: String) -> String {
            switch columnID {
            case "size":
                LocalizationManager.shared.localized("browser.column.size")
            case "type":
                LocalizationManager.shared.localized("browser.column.type")
            case "modified":
                LocalizationManager.shared.localized("browser.column.modified")
            default:
                LocalizationManager.shared.localized("browser.column.name")
            }
        }

        private func expandedIDs() -> Set<String> {
            guard let outlineView else { return [] }
            var ids: Set<String> = []
            for row in 0 ..< outlineView.numberOfRows {
                guard let node = outlineView.item(atRow: row) as? FileBrowserNode,
                      !node.isPlaceholder,
                      outlineView.isItemExpanded(node)
                else { continue }
                ids.insert(node.id)
            }
            return ids
        }

        private func restoreExpandedIDs(_ ids: Set<String>) {
            guard let outlineView else { return }
            for id in ids {
                guard let node = self.nodeByID[id] else { continue }
                outlineView.expandItem(node)
            }
        }
    }
}

private final class FileBrowserNode: NSObject {
    var item: FileItem
    var children: [FileBrowserNode] = []
    var loaded = false
    var loading = false
    var isPlaceholder: Bool
    var id: String {
        self.item.id
    }

    init(item: FileItem, isPlaceholder: Bool = false) {
        self.item = item
        self.isPlaceholder = isPlaceholder
    }

    static func placeholder(parentID: String) -> FileBrowserNode {
        FileBrowserNode(
            item: FileItem(
                name: LocalizationManager.shared.localized("browser.loading"),
                path: "\(parentID):loading",
                kind: .unknown,
                source: .local
            ),
            isPlaceholder: true
        )
    }
}

private protocol FileBrowserOutlineActionHandler: AnyObject {
    func contextMenu() -> NSMenu
    func copySelectedItems()
    func transferSelectedItems()
    func pasteItems()
    func renameSelectedItem()
    func deleteSelectedItems()
    func showSelectedInfo()
}

private final class FileBrowserNativeOutlineView: NSOutlineView {
    weak var actionHandler: FileBrowserOutlineActionHandler?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = self.convert(event.locationInWindow, from: nil)
        let clickedRow = self.row(at: point)
        if clickedRow >= 0, !self.selectedRowIndexes.contains(clickedRow) {
            self.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
        return self.actionHandler?.contextMenu()
    }

    override func keyDown(with event: NSEvent) {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifierFlags == .command, event.charactersIgnoringModifiers == "c" {
            self.actionHandler?.copySelectedItems()
            return
        }
        if modifierFlags == .command, event.charactersIgnoringModifiers == "v" {
            self.actionHandler?.pasteItems()
            return
        }
        if modifierFlags == [], event.charactersIgnoringModifiers == "\r" {
            self.actionHandler?.renameSelectedItem()
            return
        }
        if modifierFlags == [], event.charactersIgnoringModifiers == " " {
            self.actionHandler?.showSelectedInfo()
            return
        }
        if modifierFlags == [], event.charactersIgnoringModifiers == "\u{7F}" {
            self.actionHandler?.deleteSelectedItems()
            return
        }
        if modifierFlags == .command, event.charactersIgnoringModifiers == "\u{7F}" {
            self.actionHandler?.deleteSelectedItems()
            return
        }
        if modifierFlags == .command, event.charactersIgnoringModifiers == "\r" {
            self.actionHandler?.transferSelectedItems()
            return
        }
        super.keyDown(with: event)
    }
}

extension FileBrowserOutlineView.Coordinator: FileBrowserOutlineActionHandler {}

private final class FileBrowserRowView: NSTableRowView {
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false {
        didSet {
            if oldValue != self.isHovering {
                self.needsDisplay = true
            }
        }
    }

    override var isSelected: Bool {
        didSet {
            self.needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            self.removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        self.addTrackingArea(trackingArea)
        self.trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        self.isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        self.isHovering = false
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        self.drawCapsuleState()
    }

    override func drawSelection(in _: NSRect) {
        self.drawCapsuleState()
    }

    private func drawCapsuleState() {
        let rowRect = self.bounds.insetBy(dx: 6, dy: 1)
        let path = NSBezierPath(roundedRect: rowRect, xRadius: 7, yRadius: 7)
        if self.isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.17).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.20).setStroke()
            path.lineWidth = 1
            path.stroke()
        } else if self.isHovering {
            NSColor.labelColor.withAlphaComponent(0.055).setFill()
            path.fill()
        }
    }
}

private final class FileBrowserNameCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setup()
    }

    func configure(node: FileBrowserNode, source: FileSource) {
        self.imageView?.image = node.isPlaceholder ? nil : FileBrowserIconProvider.icon(for: node.item, source: source)
        self.imageView?.contentTintColor = source == .remote && node.item.kind == .folder
            ? NSColor.controlAccentColor.withAlphaComponent(0.72)
            : nil
        self.textField?.stringValue = node.isPlaceholder ? LocalizationManager.shared.localized("browser.loading") : node.item.name
        self.textField?.textColor = node.isPlaceholder ? .secondaryLabelColor : .labelColor
        self.textField?.font = .systemFont(ofSize: NSFont.systemFontSize, weight: node.isPlaceholder ? .regular : .medium)
        self.setAccessibilityLabel(node.isPlaceholder ? LocalizationManager.shared.localized("browser.loadingAccessibility") : node.item.name)
        self.setAccessibilityValue(node.isPlaceholder ? nil : self.accessibilityValue(for: node.item))
    }

    private func accessibilityValue(for item: FileItem) -> String {
        var parts = [item.kind.localizedTitle]
        if let size = item.size, item.kind != .folder {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let modifiedAt = item.modifiedAt {
            parts.append(String(format: LocalizationManager.shared.localized("browser.modifiedAccessibility"), modifiedAt.formatted(date: .abbreviated, time: .shortened)))
        }
        return parts.joined(separator: ", ")
    }

    private func setup() {
        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        self.iconView.imageScaling = .scaleProportionallyUpOrDown
        self.nameField.translatesAutoresizingMaskIntoConstraints = false
        self.nameField.lineBreakMode = .byTruncatingMiddle
        self.imageView = self.iconView
        self.textField = self.nameField
        self.addSubview(self.iconView)
        self.addSubview(self.nameField)
        NSLayoutConstraint.activate([
            self.iconView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 3),
            self.iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.iconView.widthAnchor.constraint(equalToConstant: 18),
            self.iconView.heightAnchor.constraint(equalToConstant: 18),
            self.nameField.leadingAnchor.constraint(equalTo: self.iconView.trailingAnchor, constant: 8),
            self.nameField.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -4),
            self.nameField.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        ])
    }
}

private enum FileBrowserIconProvider {
    static func icon(for item: FileItem, source: FileSource) -> NSImage {
        if source == .local {
            return NSWorkspace.shared.icon(forFile: item.path)
        }
        if item.kind == .folder, let symbol = NSImage(systemSymbolName: "folder", accessibilityDescription: nil) {
            symbol.isTemplate = true
            return symbol
        }
        return NSWorkspace.shared.icon(for: self.remoteContentType(for: item))
    }

    private static func remoteContentType(for item: FileItem) -> UTType {
        switch item.kind {
        case .folder:
            return .folder
        case .symbolicLink:
            return .aliasFile
        case .unknown:
            return .data
        case .file:
            guard let fileExtension = item.name.split(separator: ".").last.map(String.init),
                  fileExtension != item.name,
                  let contentType = UTType(filenameExtension: fileExtension)
            else {
                return .data
            }
            return contentType
        }
    }
}
