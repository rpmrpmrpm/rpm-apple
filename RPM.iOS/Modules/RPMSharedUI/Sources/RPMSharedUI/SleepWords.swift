import Foundation
import RPMKit

/// The text for the sleep timer's durations and remaining time. The iPhone and Apple TV apps share
/// it, so both show the same text for the same timer.
public enum SleepWords {
    /// "5 min", "1 hour": a menu option.
    public static func after(_ wait: Duration) -> String {
        let minutes = Int(wait.seconds / 60)
        return minutes == 60 ? Loc.get("Rpm_Sleep_OneHour") : Loc.get("Rpm_Sleep_Minutes", minutes)
    }

    /// "+5 min", "+1 hour": a button that adds to a running timer.
    public static func adding(_ wait: Duration) -> String {
        let minutes = Int(wait.seconds / 60)
        return minutes == 60 ? Loc.get("Rpm_Sleep_AddHour") : Loc.get("Rpm_Sleep_AddMinutes", minutes)
    }

    /// "14:52", or "1:02:03" from one hour up. The time is rounded up, so the last second shows
    /// 0:01 and not 0:00 while the music is still playing.
    public static func clock(_ left: Duration) -> String {
        let whole = Int(left.seconds.rounded(.up))
        let hours = whole / 3600, minutes = whole % 3600 / 60, seconds = whole % 60

        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                         : String(format: "%d:%02d", minutes, seconds)
    }
}
