import Foundation
import UserNotifications

/// Thin wrapper over local notifications (study reminders / forced-study prompts).
/// iOS cannot draw an overlay over other apps (unlike the Android fork), so the
/// reminder is a local notification; enforcement happens in-app when opened.
enum NotificationService {
    static let forcedStudyId = "ankiai.forced_study"
    static let dailyReminderId = "ankiai.daily_reminder"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Schedule a repeating "time to study" reminder every `intervalMinutes`.
    static func scheduleForcedStudy(intervalMinutes: Int, requiredCards: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [forcedStudyId])
        let content = UNMutableNotificationContent()
        content.title = "Time to study"
        content.body = "Review \(requiredCards) card\(requiredCards == 1 ? "" : "s") to stay on track."
        content.sound = .default
        let interval = max(60, Double(intervalMinutes) * 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: true)
        center.add(UNNotificationRequest(identifier: forcedStudyId, content: content, trigger: trigger))
    }

    static func cancelForcedStudy() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [forcedStudyId])
    }

    /// A daily reminder at the given hour/minute (local time).
    static func scheduleDailyReminder(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderId])
        let content = UNMutableNotificationContent()
        content.title = "AnkiAI"
        content.body = "Your cards are waiting — keep your streak going."
        content.sound = .default
        var date = DateComponents(); date.hour = hour; date.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        center.add(UNNotificationRequest(identifier: dailyReminderId, content: content, trigger: trigger))
    }

    static func cancelDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyReminderId])
    }
}
