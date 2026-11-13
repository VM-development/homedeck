import UserNotifications
import Rex5Kit

/// Posts "<device> connected to your REX5". Tapping it opens Paired devices.
@MainActor
final class TakeoverNotifier {
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(deviceName: String) {
        let content = UNMutableNotificationContent()
        content.title = "REX5"
        content.body = "\(deviceName) connected to your REX5."
        content.sound = .default
        content.userInfo = ["link": DeepLink.devices.url.absoluteString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
