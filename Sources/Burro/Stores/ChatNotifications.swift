import Foundation
import UserNotifications
import BurroCore

@MainActor final class ChatNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ChatNotifications()
    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Burro notification permission: %@", error.localizedDescription) }
        }
    }
    func send(_ session: AgentSession) {
        let content = UNMutableNotificationContent()
        content.title = "Chat finished"
        content.subtitle = session.title
        content.body = "\(session.remote?.hostName ?? "This Mac") · \(session.provider.rawValue)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Burro notification delivery: %@", error.localizedDescription) }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
