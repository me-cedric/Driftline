import DriftlineCore
import SwiftUI

struct InspectorView: View {
    var file: FileItem?
    var session: ConnectionSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InspectorSection(title: "Selection") {
                    if let file {
                        LabeledContent("Name", value: file.name)
                        LabeledContent("Path", value: file.path)
                        LabeledContent("Type", value: file.kind.rawValue.capitalized)
                        LabeledContent("Size", value: file.size.map(ByteCountFormatter.string) ?? "--")
                        LabeledContent("Source", value: file.source.rawValue.capitalized)
                    } else {
                        Text("Select a local or remote item.")
                            .foregroundStyle(.secondary)
                    }
                }

                InspectorSection(title: "Connection") {
                    LabeledContent("State", value: String(describing: self.session.state))
                    LabeledContent("Protocol", value: self.session.protocolKind?.rawValue.uppercased() ?? "--")
                    LabeledContent("Local Path", value: self.session.localPath)
                    LabeledContent("Remote Path", value: self.session.remotePath)
                }
            }
            .padding(16)
        }
    }
}
