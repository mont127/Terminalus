import AppKit
import UserNotifications

/// Posts user notifications. UNUserNotificationCenter crashes outside an .app bundle, so it is only
/// used when running from Terminalus.app; otherwise it falls back to bouncing the Dock icon.
@MainActor
enum NotificationHelper {
    static var canUseNotificationCenter: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private static var authorized: Bool?

    static func post(title: String, body: String) {
        guard canUseNotificationCenter else {
            NSApp.requestUserAttention(.informationalRequest)
            return
        }
        let center = UNUserNotificationCenter.current()
        let send = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if authorized == true {
            send()
            return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                authorized = granted
                if granted { send() } else { NSApp.requestUserAttention(.informationalRequest) }
            }
        }
    }
}
