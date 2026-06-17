#if canImport(WidgetKit)
    import DriftlineCore
    import SwiftUI
    import WidgetKit

    public struct DriftlineStatusEntry: TimelineEntry {
        public var date: Date
        public var state: DriftlineIntegrationState

        public init(date: Date, state: DriftlineIntegrationState) {
            self.date = date
            self.state = state
        }

        public static var placeholder: DriftlineStatusEntry {
            DriftlineStatusEntry(date: Date(), state: DriftlineIntegrationState())
        }

        public static var transferringPreview: DriftlineStatusEntry {
            DriftlineStatusEntry(
                date: Date(),
                state: DriftlineIntegrationState(
                    recents: [
                        DriftlineIntegrationConnectionSummary(
                            id: "preview-recent",
                            displayName: "Files",
                            protocolKind: .sftp,
                            host: "files.example.com",
                            port: 22,
                            username: "demo",
                            path: "/incoming",
                            lastUsedAt: Date(),
                            isFavorite: false
                        ),
                    ],
                    favorites: [
                        DriftlineIntegrationConnectionSummary(
                            id: "preview-favorite",
                            displayName: "Production",
                            protocolKind: .sftp,
                            host: "example.com",
                            port: 22,
                            username: "deploy",
                            path: "/",
                            lastUsedAt: Date(),
                            isFavorite: true
                        ),
                    ],
                    status: DriftlineIntegrationStatusSnapshot(
                        activeTransferCount: 2,
                        queuedTransferCount: 1,
                        failedTransferCount: 0,
                        currentState: .transferring
                    )
                )
            )
        }

        public static var errorPreview: DriftlineStatusEntry {
            DriftlineStatusEntry(
                date: Date(),
                state: DriftlineIntegrationState(
                    status: DriftlineIntegrationStatusSnapshot(
                        activeTransferCount: 0,
                        queuedTransferCount: 0,
                        failedTransferCount: 1,
                        currentState: .error
                    )
                )
            )
        }
    }

    public struct DriftlineStatusTimelineProvider: TimelineProvider {
        private let snapshotProvider: DriftlineWidgetSnapshotProvider

        public init(snapshotProvider: DriftlineWidgetSnapshotProvider = DriftlineWidgetSnapshotProvider()) {
            self.snapshotProvider = snapshotProvider
        }

        public func placeholder(in _: Context) -> DriftlineStatusEntry {
            .placeholder
        }

        public func getSnapshot(in _: Context, completion: @escaping (DriftlineStatusEntry) -> Void) {
            Task {
                await completion(DriftlineStatusEntry(date: Date(), state: self.snapshotProvider.snapshot()))
            }
        }

        public func getTimeline(in _: Context, completion: @escaping (Timeline<DriftlineStatusEntry>) -> Void) {
            Task {
                let entry = await DriftlineStatusEntry(date: Date(), state: self.snapshotProvider.snapshot())
                let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date.addingTimeInterval(900)
                completion(Timeline(entries: [entry], policy: .after(refreshDate)))
            }
        }
    }

    public struct DriftlineStatusWidget: Widget {
        public let kind = "DriftlineStatusWidget"

        public init() {}

        public var body: some WidgetConfiguration {
            StaticConfiguration(kind: self.kind, provider: DriftlineStatusTimelineProvider()) { entry in
                DriftlineStatusWidgetView(entry: entry)
            }
            .configurationDisplayName("Driftline Status")
            .description("Shows transfer status and safe recent connection actions.")
            .supportedFamilies([.systemSmall, .systemMedium])
        }
    }

    struct DriftlineStatusWidgetView: View {
        @Environment(\.widgetFamily) private var family

        var entry: DriftlineStatusEntry

        var body: some View {
            switch self.family {
            case .systemMedium:
                self.medium
            default:
                self.small
            }
        }

        private var small: some View {
            Link(destination: DriftlineWidgetActionURLBuilder.openDriftlineURL) {
                VStack(alignment: .leading, spacing: 10) {
                    self.header
                    Spacer(minLength: 4)
                    Text(self.statusTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(self.transferSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .containerBackground(.fill.tertiary, for: .widget)
            }
        }

        private var medium: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    self.header
                    Spacer()
                    Link("Open", destination: DriftlineWidgetActionURLBuilder.openDriftlineURL)
                        .font(.caption.weight(.semibold))
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(self.statusTitle)
                        .font(.headline)
                    Text(self.transferSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                let actions = DriftlineWidgetActionURLBuilder.connectionActions(from: self.entry.state, limit: 2)
                if actions.isEmpty {
                    Text("No recent connections")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(actions) { action in
                        Link(destination: action.url) {
                            HStack(spacing: 8) {
                                Image(systemName: action.summary.isFavorite ? "star.fill" : "clock")
                                    .foregroundStyle(action.summary.isFavorite ? .yellow : .secondary)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(action.summary.displayName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(action.summary.host)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.fill.tertiary, for: .widget)
        }

        private var header: some View {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text("Driftline")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
            }
        }

        private var statusTitle: String {
            switch self.entry.state.status.currentState {
            case .idle:
                "Idle"
            case .transferring:
                "Transferring"
            case .error:
                "Error"
            }
        }

        private var transferSummary: String {
            let status = self.entry.state.status
            return "\(status.activeTransferCount) active, \(status.queuedTransferCount) queued, \(status.failedTransferCount) failed"
        }
    }
#endif
