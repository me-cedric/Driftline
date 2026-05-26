import SwiftUI

struct DriftlineCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Connection") { model.beginQuickConnect() }
                .keyboardShortcut("n")
            Button("New Tab") { model.newTab() }
                .keyboardShortcut("t")
            Button("Close Tab") { model.closeSelectedTab() }
                .keyboardShortcut("w")
        }

        CommandMenu("Connection") {
            Button("Quick Connect") { model.beginQuickConnect() }
                .keyboardShortcut("l")
            Button("Connect Selected Server") { model.connectToSelectedServer() }
            Button("Open SSH in Terminal") { model.openTerminalSession() }
            Button("Disconnect") { model.disconnect() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Reconnect Last") { model.reconnectLastServer() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Save Current Connection") { model.saveCurrentConnectionAsBookmark() }
                .keyboardShortcut("s", modifiers: [.command, .option])
        }

        CommandMenu("Transfer") {
            Button("Upload") { model.uploadSelectedItem() }
                .keyboardShortcut("u", modifiers: [.command, .option])
            Button("Download") { model.downloadSelectedItem() }
                .keyboardShortcut("d", modifiers: [.command, .option])
            Button("Show Inspector") { model.preferences.showInspector.toggle() }
                .keyboardShortcut("i")
            Button("View Options") { model.showViewOptions.toggle() }
                .keyboardShortcut("j")
        }

        CommandGroup(replacing: .appInfo) {
            Button("About Driftline") { model.showAbout = true }
        }
    }
}
