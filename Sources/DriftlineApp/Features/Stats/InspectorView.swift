import DriftlineCore
import SwiftUI

struct InspectorView: View {
    var file: FileItem?
    var session: ConnectionSession

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    InspectorSection(title: LocalizationManager.shared.localized("inspector.selection")) {
                        if let file {
                            LabeledContent(LocalizationManager.shared.localized("inspector.name"), value: file.name)
                            LabeledContent(LocalizationManager.shared.localized("inspector.path"), value: file.path)
                            LabeledContent(LocalizationManager.shared.localized("inspector.type"), value: file.kind.localizedTitle)
                            LabeledContent(LocalizationManager.shared.localized("inspector.size"), value: file.size.map(ByteCountFormatter.string) ?? "--")
                            LabeledContent(LocalizationManager.shared.localized("inspector.source"), value: file.source.localizedTitle)
                        } else {
                            Text(LocalizationManager.shared.localized("inspector.selectItem"))
                                .foregroundStyle(.secondary)
                        }
                    }

                    InspectorSection(title: LocalizationManager.shared.localized("inspector.connection")) {
                        LabeledContent(LocalizationManager.shared.localized("inspector.state"), value: self.session.state.localizedTitle)
                        LabeledContent(LocalizationManager.shared.localized("inspector.protocol"), value: self.session.protocolKind?.rawValue.uppercased() ?? "--")
                        LabeledContent(LocalizationManager.shared.localized("inspector.localPath"), value: self.session.localPath)
                        LabeledContent(LocalizationManager.shared.localized("inspector.remotePath"), value: self.session.remotePath)
                    }
                }
                .frame(width: max(0, proxy.size.width - 32), alignment: .topLeading)
                .padding(16)
            }
        }
    }
}
