import Foundation

/// Locale-driven localization. Keys are the English strings (so an unmapped key
/// falls back to readable English), with Hebrew translations ported from the
/// Android fork's `values-iw/ai_strings.xml`. SwiftUI applies RTL automatically
/// when the device language is Hebrew.
///
/// Testable: `Loc.t(key, lang:)` is pure given an explicit language code.
public enum Loc {
    /// Current UI language code ("he", "en", …).
    public static var currentLang: String {
        if #available(iOS 16, *) {
            return Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            return Locale.current.languageCode ?? "en"
        }
    }

    /// Localize `key`. Hebrew ("he"/"iw") uses the catalog; everything else returns
    /// the key (which is the English text).
    public static func t(_ key: String, lang: String = currentLang) -> String {
        if lang.hasPrefix("he") || lang.hasPrefix("iw") {
            return hebrew[key] ?? key
        }
        return key
    }

    /// Hebrew catalog (English key → Hebrew), ported from the Android fork.
    static let hebrew: [String: String] = [
        // Tabs / navigation
        "Decks": "חפיסות",
        "Browse": "עיון",
        "Insights": "תובנות",
        "Settings": "הגדרות",
        // Common actions
        "Send": "שלח",
        "Cancel": "בטל",
        "Save": "שמור",
        "Done": "סיום",
        "Create": "צור",
        "Delete": "מחק",
        "Rename": "שנה שם",
        "Finish": "סיום",
        "Connect": "התחבר",
        "Log out": "התנתק",
        // Reviewer
        "Show Answer": "הצג תשובה",
        "Again": "שוב",
        "Hard": "קשה",
        "Good": "טוב",
        "Easy": "קל",
        "Edit card": "ערוך כרטיס",
        "Bury card": "קבור כרטיס",
        "Ask Claude": "שאל את קלוד",
        "No cards in this deck.": "אין כרטיסים בחפיסה זו.",
        // Deck list
        "Custom Study": "לימוד מותאם",
        "Create Cards with AI": "צור כרטיסים עם AI",
        "Rename deck": "שנה שם חפיסה",
        // Chat / creator
        "Ask a question…": "שאל שאלה…",
        "Describe what to learn…": "תאר מה ללמוד…",
        "Connect Claude AI": "חבר את Claude AI",
        "Create Cards with AI ": "צור כרטיסים עם AI",
        // Settings
        "Claude API Key": "מפתח API של קלוד",
        "Test connection": "בדוק חיבור",
        "AnkiWeb sync": "סנכרון AnkiWeb",
        "Backup & restore": "גיבוי ושחזור",
        "Study reminders": "תזכורות לימוד",
        "Budget": "תקציב",
        "Remove key": "הסר מפתח",
        "Connected": "מחובר",
        // Forced study
        "Forced Study": "חיוב למידה",
        "Forced study & reminders": "חיוב למידה ותזכורות",
        "Enable forced study": "הפעל חיוב למידה",
        "Forced study": "חיוב למידה",
        "Session complete!": "המפגש הושלם!",
        "Time to study": "הגיע זמן ללמוד",
        // Accessibility
        "new": "חדשים",
        "learning": "בלימוד",
        "due": "לחזרה",
        "Card actions": "פעולות כרטיס",
    ]
}

public extension String {
    /// Convenience: `"Send".loc` → localized for the current device language.
    var loc: String { Loc.t(self) }
}
