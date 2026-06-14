import DriftlineCore
import SwiftUI

struct SyncPreviewView: View {
    var preview: SyncPreview
    var onClose: () -> Void
    var onRunPlan: (SyncRunPlan) -> Void

    @State private var selectedLocalUploads: Set<String>
    @State private var selectedRemoteDownloads: Set<String>
    @State private var changedChoices: [String: SyncChangedChoice]
    @State private var conflictPolicy: SyncConflictPolicy = .ask

    init(preview: SyncPreview, onClose: @escaping () -> Void, onRunPlan: @escaping (SyncRunPlan) -> Void) {
        self.preview = preview
        self.onClose = onClose
        self.onRunPlan = onRunPlan
        self._selectedLocalUploads = State(initialValue: Set(preview.localOnly.map(\.id)))
        self._selectedRemoteDownloads = State(initialValue: Set(preview.remoteOnly.map(\.id)))
        self._changedChoices = State(initialValue: Dictionary(uniqueKeysWithValues: preview.changed.map { ($0.id, SyncChangedChoice.skip) }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(LocalizationManager.shared.localized("menu.compareFolders"), systemImage: "arrow.left.arrow.right")
                    .font(.title2.bold())
                Spacer()
                Button(LocalizationManager.shared.localized("sync.done"), action: self.onClose)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint(LocalizationManager.shared.localized("sync.closeHint"))
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text(LocalizationManager.shared.localized("browser.local"))
                        .foregroundStyle(.secondary)
                    Text(self.preview.localPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                GridRow {
                    Text(LocalizationManager.shared.localized("browser.remote"))
                        .foregroundStyle(.secondary)
                    Text(self.preview.remotePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack(spacing: 12) {
                self.stat("\(self.preview.matchingCount)", LocalizationManager.shared.localized("sync.matching"))
                self.stat("\(self.preview.localOnly.count)", LocalizationManager.shared.localized("sync.localOnly"))
                self.stat("\(self.preview.remoteOnly.count)", LocalizationManager.shared.localized("sync.remoteOnly"))
                self.stat("\(self.preview.changed.count)", LocalizationManager.shared.localized("sync.changed"))
            }

            Divider()

            HStack {
                Picker(LocalizationManager.shared.localized("sync.changedConflicts"), selection: self.$conflictPolicy) {
                    ForEach(SyncConflictPolicy.allCases) { policy in
                        Text(policy.localizedTitle).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint(LocalizationManager.shared.localized("sync.conflictHint"))

                Spacer()

                Text(String(format: LocalizationManager.shared.localized("sync.planned"), self.plan.uploads.count + self.plan.downloads.count))
                    .foregroundStyle(.secondary)

                Button(LocalizationManager.shared.localized("sync.runPlan")) {
                    self.onRunPlan(self.plan)
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.plan.uploads.isEmpty && self.plan.downloads.isEmpty)
                .accessibilityHint(LocalizationManager.shared.localized("sync.runPlanHint"))
            }

            HStack(alignment: .top, spacing: 18) {
                self.selectableSection(
                    title: LocalizationManager.shared.localized("sync.onlyLocal"),
                    items: self.preview.localOnly,
                    selection: self.$selectedLocalUploads,
                    emptyText: LocalizationManager.shared.localized("sync.nothingToUpload"),
                    target: LocalizationManager.shared.localized("browser.upload")
                )
                self.selectableSection(
                    title: LocalizationManager.shared.localized("sync.onlyRemote"),
                    items: self.preview.remoteOnly,
                    selection: self.$selectedRemoteDownloads,
                    emptyText: LocalizationManager.shared.localized("sync.nothingToDownload"),
                    target: LocalizationManager.shared.localized("browser.download")
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

    private var plan: SyncRunPlan {
        var uploads = self.preview.localOnly.filter { self.selectedLocalUploads.contains($0.id) }
        var downloads = self.preview.remoteOnly.filter { self.selectedRemoteDownloads.contains($0.id) }

        if self.conflictPolicy != .skipChanged {
            for difference in self.preview.changed {
                switch self.changedChoices[difference.id] ?? .skip {
                case .skip:
                    break
                case .uploadLocal:
                    uploads.append(difference.local)
                case .downloadRemote:
                    downloads.append(difference.remote)
                }
            }
        }

        return SyncRunPlan(uploads: uploads, downloads: downloads, conflictPolicy: self.conflictPolicy.transferPolicy)
    }

    private func selectableSection(title: String, items: [FileItem], selection: Binding<Set<String>>, emptyText: String, target: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(selection.wrappedValue.count == items.count ? LocalizationManager.shared.localized("sync.none") : LocalizationManager.shared.localized("sync.all")) {
                    if selection.wrappedValue.count == items.count {
                        selection.wrappedValue = []
                    } else {
                        selection.wrappedValue = Set(items.map(\.id))
                    }
                }
                .disabled(items.isEmpty)
                .accessibilityHint(LocalizationManager.shared.localized("sync.toggleAllHint"))
            }
            self.selectableItemList(items: items, selection: selection, emptyText: emptyText, target: target)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var changedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(LocalizationManager.shared.localized("sync.changed"))
                    .font(.headline)
                Spacer()
                Menu(LocalizationManager.shared.localized("sync.setAll")) {
                    Button(LocalizationManager.shared.localized("sync.skip")) {
                        self.setAllChanged(.skip)
                    }
                    .disabled(self.preview.changed.isEmpty)
                    Button(LocalizationManager.shared.localized("sync.uploadLocalVersions")) {
                        self.setAllChanged(.uploadLocal)
                    }
                    .disabled(self.preview.changed.isEmpty)
                    Button(LocalizationManager.shared.localized("sync.downloadRemoteVersions")) {
                        self.setAllChanged(.downloadRemote)
                    }
                    .disabled(self.preview.changed.isEmpty)
                }
                .accessibilityHint(LocalizationManager.shared.localized("sync.setAllHint"))
            }
            if self.preview.changed.isEmpty {
                Text(LocalizationManager.shared.localized("sync.noDifferences"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
            } else {
                List(self.preview.changed) { difference in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(difference.name)
                                .lineLimit(1)
                            Spacer()
                            Picker(LocalizationManager.shared.localized("sync.action"), selection: self.changedChoiceBinding(for: difference)) {
                                ForEach(SyncChangedChoice.allCases) { choice in
                                    Text(choice.localizedTitle).tag(choice)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                            .disabled(self.conflictPolicy == .skipChanged)
                        }
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

    private func selectableItemList(items: [FileItem], selection: Binding<Set<String>>, emptyText: String, target: String) -> some View {
        Group {
            if items.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
            } else {
                List(items) { item in
                    Toggle(isOn: Binding(
                        get: { selection.wrappedValue.contains(item.id) },
                        set: { isSelected in
                            if isSelected {
                                selection.wrappedValue.insert(item.id)
                            } else {
                                selection.wrappedValue.remove(item.id)
                            }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: item.kind == .folder ? "folder" : "doc")
                                .foregroundStyle(.secondary)
                            Text(item.name)
                                .lineLimit(1)
                            Spacer()
                            Text(target)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(item.name)
                    .accessibilityValue(item.kind.localizedTitle)
                }
                .frame(minHeight: 250)
            }
        }
    }

    private func changedChoiceBinding(for difference: SyncDifference) -> Binding<SyncChangedChoice> {
        Binding(
            get: { self.changedChoices[difference.id] ?? .skip },
            set: { self.changedChoices[difference.id] = $0 }
        )
    }

    private func setAllChanged(_ choice: SyncChangedChoice) {
        for difference in self.preview.changed {
            self.changedChoices[difference.id] = choice
        }
    }
}

struct SyncRunPlan {
    var uploads: [FileItem]
    var downloads: [FileItem]
    var conflictPolicy: TransferConflictPolicy
}

enum SyncConflictPolicy: String, CaseIterable, Identifiable {
    case ask
    case replace
    case skipChanged

    var id: String {
        self.rawValue
    }

    var localizedTitle: String {
        switch self {
        case .ask:
            LocalizationManager.shared.localized("sync.ask")
        case .replace:
            LocalizationManager.shared.localized("sync.replace")
        case .skipChanged:
            LocalizationManager.shared.localized("sync.skipChanged")
        }
    }

    var transferPolicy: TransferConflictPolicy {
        switch self {
        case .ask:
            .ask
        case .replace:
            .replace
        case .skipChanged:
            .skip
        }
    }
}

enum SyncChangedChoice: String, CaseIterable, Identifiable {
    case skip
    case uploadLocal
    case downloadRemote

    var id: String {
        self.rawValue
    }

    var localizedTitle: String {
        switch self {
        case .skip:
            LocalizationManager.shared.localized("sync.skip")
        case .uploadLocal:
            LocalizationManager.shared.localized("browser.upload")
        case .downloadRemote:
            LocalizationManager.shared.localized("browser.download")
        }
    }
}
