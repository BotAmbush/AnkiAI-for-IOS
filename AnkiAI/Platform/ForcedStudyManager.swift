import Foundation
import Combine

/// Forced-study configuration, mirroring the Android fork's `ForcedStudySettings`
/// (UserDefaults-backed). iOS adaptation: a repeating notification + an in-app
/// session that requires N reviews; snooze postpones it.
public final class ForcedStudyStore {
    private let d: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.d = defaults }

    public var isEnabled: Bool {
        get { d.bool(forKey: "fs_enabled") }
        set { d.set(newValue, forKey: "fs_enabled") }
    }
    public var intervalMinutes: Int {
        get { (d.object(forKey: "fs_interval") as? Int) ?? 60 }
        set { d.set(newValue, forKey: "fs_interval") }
    }
    public var requiredCards: Int {
        get { (d.object(forKey: "fs_required") as? Int) ?? 10 }
        set { d.set(newValue, forKey: "fs_required") }
    }
    public var deckName: String? {
        get { d.string(forKey: "fs_deck") }
        set { d.set(newValue, forKey: "fs_deck") }
    }
    public var snoozeEnabled: Bool {
        get { d.bool(forKey: "fs_snooze") }
        set { d.set(newValue, forKey: "fs_snooze") }
    }
    public var maxSnoozes: Int {
        get { (d.object(forKey: "fs_maxsnooze") as? Int) ?? 2 }
        set { d.set(newValue, forKey: "fs_maxsnooze") }
    }
    public var snoozeDurationMin: Int {
        get { (d.object(forKey: "fs_snoozedur") as? Int) ?? 5 }
        set { d.set(newValue, forKey: "fs_snoozedur") }
    }
    public var lastCompleted: Date {
        get { Date(timeIntervalSince1970: d.double(forKey: "fs_last")) }
        set { d.set(newValue.timeIntervalSince1970, forKey: "fs_last") }
    }
    public var snoozedUntil: Date {
        get { Date(timeIntervalSince1970: d.double(forKey: "fs_snoozeuntil")) }
        set { d.set(newValue.timeIntervalSince1970, forKey: "fs_snoozeuntil") }
    }
    public var snoozesUsed: Int {
        get { d.integer(forKey: "fs_snoozesused") }
        set { d.set(newValue, forKey: "fs_snoozesused") }
    }
}

/// Drives whether a forced-study session is currently due, plus snooze/complete.
@MainActor
public final class ForcedStudyManager: ObservableObject {
    @Published public private(set) var sessionDue = false
    public let store: ForcedStudyStore

    public init(store: ForcedStudyStore = ForcedStudyStore()) {
        self.store = store
        refresh()
    }

    /// Recompute whether the session is due (call on launch / foreground).
    public func refresh() {
        guard store.isEnabled else { sessionDue = false; return }
        let now = Date()
        if now < store.snoozedUntil { sessionDue = false; return }
        sessionDue = now.timeIntervalSince(store.lastCompleted) >= Double(store.intervalMinutes) * 60
    }

    public var canSnooze: Bool { store.snoozeEnabled && store.snoozesUsed < store.maxSnoozes }

    public func snooze() {
        store.snoozedUntil = Date().addingTimeInterval(Double(store.snoozeDurationMin) * 60)
        store.snoozesUsed += 1
        sessionDue = false
    }

    public func complete() {
        store.lastCompleted = Date()
        store.snoozesUsed = 0
        store.snoozedUntil = Date(timeIntervalSince1970: 0)
        sessionDue = false
    }

    /// Force a session now (manual trigger / from a tapped notification).
    public func triggerNow() {
        store.lastCompleted = Date(timeIntervalSince1970: 0)
        store.snoozedUntil = Date(timeIntervalSince1970: 0)
        refresh()
    }

    /// Apply the current config: (re)schedule or cancel the notification.
    public func apply() async {
        if store.isEnabled {
            _ = await NotificationService.requestAuthorization()
            NotificationService.scheduleForcedStudy(intervalMinutes: store.intervalMinutes,
                                                    requiredCards: store.requiredCards)
        } else {
            NotificationService.cancelForcedStudy()
        }
        refresh()
    }
}
