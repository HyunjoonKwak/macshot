import UserNotifications

/// Sends macOS Notification Center alerts after capture actions.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "showCaptureNotification")
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyCaptured(filename: String? = nil) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notify.captured", comment: "")
        content.body = filename ?? NSLocalizedString("notify.copied", comment: "")
        content.sound = nil  // app already plays its own sound

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notifySaved(path: String) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notify.saved", comment: "")
        content.body = (path as NSString).lastPathComponent
        content.sound = nil

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Show notification even when app is foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
