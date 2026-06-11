import Foundation

/// "Peak hours" — the 5:00–11:00 America/Los_Angeles window when Anthropic's
/// load is heaviest. The window is *anchored to Pacific* (a fixed absolute
/// interval), but the boundary times shown in the menu are converted to the
/// user's local clock. Named time zones handle DST automatically.
enum PeakHours {
    static let startHour = 5
    static let endHour = 11

    /// Defines the window. Fixed to Pacific — this is where the real peak is.
    private static let peakZone = TimeZone(identifier: "America/Los_Angeles")!
    /// Used only to display boundary times on the user's wall clock.
    private static var localZone: TimeZone { .autoupdatingCurrent }

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = peakZone
        return cal
    }

    /// True if `date` falls inside the peak window (evaluated in Pacific time).
    static func isActive(at date: Date = Date()) -> Bool {
        let h = calendar.component(.hour, from: date)
        return h >= startHour && h < endHour
    }

    /// The next instant the window flips: its end if currently active,
    /// otherwise its next start.
    static func nextBoundary(from date: Date = Date()) -> Date {
        let targetHour = isActive(at: date) ? endHour : startHour
        let match = DateComponents(hour: targetHour, minute: 0, second: 0)
        return calendar.nextDate(after: date, matching: match, matchingPolicy: .nextTime) ?? date
    }

    /// A menu-ready status string with the boundary shown in the user's local
    /// time, e.g. "active (until 2 AM)" or "next at 8 PM".
    static func statusLabel(at date: Date = Date()) -> String {
        let df = DateFormatter()
        df.timeZone = localZone
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "h a"
        let boundary = df.string(from: nextBoundary(from: date))
        return isActive(at: date)
            ? "active (until \(boundary))"
            : "next at \(boundary)"
    }
}
