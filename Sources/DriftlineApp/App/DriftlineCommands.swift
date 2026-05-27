import SwiftUI

struct DriftlineCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Connection") { self.model.beginQuickConnect() }
                .keyboardShortcut("n")
            Button("New Tab") { self.model.newTab() }
                .keyboardShortcut("t")
            Button("Close Tab") { self.model.closeSelectedTab() }
                .keyboardShortcut("w")
        }

        CommandMenu("Connection") {
            Button("Quick Connect") { self.model.beginQuickConnect() }
                .keyboardShortcut("l")
            Button("Connect Selected Server") { self.model.connectToSelectedServer() }
            Button("Open SSH in Terminal") { self.model.openTerminalSession() }
            Button("Disconnect") { self.model.disconnect() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Reconnect Last") { self.model.reconnectLastServer() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Save Current Connection") { self.model.saveCurrentConnectionAsBookmark() }
                .keyboardShortcut("s", modifiers: [.command, .option])
        }

        CommandMenu("Transfer") {
            Button("Upload") { self.model.uploadSelectedItem() }
                .keyboardShortcut("u", modifiers: [.command, .option])
            Button("Download") { self.model.downloadSelectedItem() }
                .keyboardShortcut("d", modifiers: [.command, .option])
            Button("Show Inspector") { self.model.preferences.showInspector.toggle() }
                .keyboardShortcut("i")
            Button("View Options") { self.model.showViewOptions.toggle() }
                .keyboardShortcut("j")
        }

        CommandGroup(replacing: .appInfo) {
            Button("About Driftline") { self.model.showAbout = true }
        }
    }
}
