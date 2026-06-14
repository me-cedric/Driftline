import DriftlineCore
import SwiftUI

struct SyncPreviewView: View {
    var preview: SyncPreview
    var onClose: () -> Void
    var onUpload: ([FileItem]) -> Void
    var onDownload: ([FileItem]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Compare Folders", systemImage: "arrow.left.arrow.right")
                    .font(.title2.bold())
                Spacer()
                Button("Done", action: self.onClose)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Closes the folder comparison.")
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Local")
                        .foregroundStyle(.secondary)
                    Text(self.preview.localPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                GridRow {
                    Text("Remote")
                        .foregroundStyle(.secondary)
                    Text(self.preview.remotePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack(spacing: 12) {
                self.stat("\(self.preview.matchingCount)", "Matching")
                self.stat("\(self.preview.localOnly.count)", "Local only")
                self.stat("\(self.preview.remoteOnly.count)", "Remote only")
                self.stat("\(self.preview.changed.count)", "Changed")
            }

            Divider()

            HStack(alignment: .top, spacing: 18) {
                self.section(
                    title: "Only Local",
                    items: self.preview.localOnly,
                    emptyText: "Nothing to upload.",
                    actionTitle: "Upload All",
                    action: { self.onUpload(self.preview.localOnly) }
                )
                self.section(
                    title: "Only Remote",
                    items: self.preview.remoteOnly,
                    emptyText: "Nothing to download.",
                    actionTitle: "Download All",
                    action: { self.onDownload(self.preview.remoteOnly) }
                )
                self.changedSection
            }
        }
        .padding(24)
        .frame(width: 780)
        .frame(minHeight: 460)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit().bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func section(title: String, items: [FileItem], emptyText: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(actionTitle, action: action)
                    .disabled(items.isEmpty)
                    .accessibilityHint("Starts transfers for all items in this section.")
            }
            self.itemList(items: items, emptyText: emptyText)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var changedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Changed")
                    .font(.headline)
                Spacer()
                Menu("Transfer All") {
                    Button("Upload Local Versions") {
                        self.onUpload(self.preview.changed.map(\.local))
                    }
                    .disabled(self.preview.changed.isEmpty)
                    Button("Download Remote Versions") {
                        self.onDownload(self.preview.changed.map(\.remote))
                    }
                    .disabled(self.preview.changed.isEmpty)
                }
                .accessibilityHint("Choose whether local or remote changed versions should win.")
            }
            if self.preview.changed.isEmpty {
                Text("No size or type differences.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
            } else {
                List(self.preview.changed) { difference in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(difference.name)
                            .lineLimit(1)
                        Text(difference.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .frame(minHeight: 250)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func itemList(items: [FileItem], emptyText: String) -> some View {
        Group {
            if items.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
            } else {
                List(items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.kind == .folder ? "folder" : "doc")
                            .foregroundStyle(.secondary)
                        Text(item.name)
                            .lineLimit(1)
                        Spacer()
                    }
                    .accessibilityLabel(item.name)
                    .accessibilityValue(item.kind.rawValue.capitalized)
                }
                .frame(minHeight: 250)
            }
        }
    }
}
