import AppKit
import UserNotifications

final class AppNotificationController: @unchecked Sendable {
    @MainActor
    func notifyIfBackground(isEnabled: Bool, title: String, body: String, identifier: String = UUID().uuidString) {
        guard isEnabled, !NSApp.isActive else { return }

        Task {
            await self.deliver(title: title, body: body, identifier: identifier)
        }
    }

    private func deliver(title: String, body: String, identifier: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let isAllowed: Bool = switch settings.authorizationStatus {
        case .notDetermined:
            await (try? center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            true
        case .denied:
            false
        @unknown default:
            false
        }

        guard isAllowed else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await center.add(request)
    }
}
