import AppKit
import DriftlineCore
import SwiftUI

struct DriftlineCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(LocalizationManager.shared.localized("menu.newConnection")) { self.model.beginQuickConnect() }
                .keyboardShortcut("n")
            Button(LocalizationManager.shared.localized("menu.newTab")) { self.model.newTab() }
                .keyboardShortcut("t")
            Button(LocalizationManager.shared.localized("menu.closeTab")) { self.model.closeSelectedTab() }
                .keyboardShortcut("w")
        }

        CommandMenu(LocalizationManager.shared.localized("menu.connection")) {
            Button(LocalizationManager.shared.localized("menu.quickConnect")) { self.model.beginQuickConnect() }
                .keyboardShortcut("l")
            Button(LocalizationManager.shared.localized("menu.connectSelected")) { self.model.connectToSelectedServer() }
            Button(LocalizationManager.shared.localized("menu.openSSH")) { self.model.openTerminalSession() }
            Button(LocalizationManager.shared.localized("connection.disconnect")) { self.model.disconnect() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button(LocalizationManager.shared.localized("menu.reconnectLast")) { self.model.reconnectLastServer() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(LocalizationManager.shared.localized("menu.saveConnection")) { self.model.saveCurrentConnectionAsBookmark() }
                .keyboardShortcut("s", modifiers: [.command, .option])
        }

        CommandMenu(LocalizationManager.shared.localized("menu.transfer")) {
            Button(LocalizationManager.shared.localized("menu.upload")) { self.model.uploadSelectedItem() }
                .keyboardShortcut("u", modifiers: [.command, .option])
            Button(LocalizationManager.shared.localized("menu.download")) { self.model.downloadSelectedItem() }
                .keyboardShortcut("d", modifiers: [.command, .option])
            Button(LocalizationManager.shared.localized("menu.compareFolders")) { self.model.prepareSyncPreview() }
                .keyboardShortcut("=", modifiers: [.command, .option])
                .disabled(self.model.session.state != .connected)
            Button(LocalizationManager.shared.localized("menu.showInspector")) { self.model.preferences.showInspector.toggle() }
                .keyboardShortcut("i")
            Button(LocalizationManager.shared.localized("menu.viewOptions")) { self.model.showViewOptions.toggle() }
                .keyboardShortcut("j")
        }

        CommandMenu(LocalizationManager.shared.localized("menu.help")) {
            Button(LocalizationManager.shared.localized("menu.checkUpdates")) { self.model.checkForUpdates(showNoUpdateMessage: true) }
                .disabled(self.model.isCheckingForUpdates)
            Button(LocalizationManager.shared.localized("menu.revealDiagnostics")) { self.model.revealDiagnosticsLog() }
        }

        CommandGroup(replacing: .pasteboard) {
            Button(LocalizationManager.shared.localized("menu.cut")) {
                Self.sendTextCommandIfEditing(#selector(NSText.cut(_:)))
            }
            .keyboardShortcut("x")
            Button(LocalizationManager.shared.localized("menu.copy")) { self.copy() }
                .keyboardShortcut("c")
            Button(LocalizationManager.shared.localized("menu.paste")) { self.paste() }
                .keyboardShortcut("v")
            Button(LocalizationManager.shared.localized("menu.selectAll")) {
                Self.sendTextCommandIfEditing(#selector(NSText.selectAll(_:)))
            }
            .keyboardShortcut("a")
        }

        CommandGroup(replacing: .appInfo) {
            Button(LocalizationManager.shared.localized("menu.aboutDriftline")) { self.model.showAbout = true }
        }
    }

    private func copy() {
        if Self.sendTextCommandIfEditing(#selector(NSText.copy(_:))) {
            return
        }
        self.model.copySelectedItems()
    }

    private func paste() {
        if Self.sendTextCommandIfEditing(#selector(NSText.paste(_:))) {
            return
        }
        self.model.pasteCopiedItemsIntoActivePane()
    }

    @discardableResult
    private static func sendTextCommandIfEditing(_ selector: Selector) -> Bool {
        guard self.isTextEditingActive else { return false }
        NSApp.sendAction(selector, to: nil, from: nil)
        return true
    }

    private static var isTextEditingActive: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }
}
