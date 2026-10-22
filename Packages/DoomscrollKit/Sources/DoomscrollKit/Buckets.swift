import Foundation

/// iOS reports usage only as threshold crossings (DeviceActivityEvent), so the app registers one event per
/// 15-minute bucket of the day. This is the same model the Android app uses, which keeps the leaderboard fair.
public enum Buckets {
    public static let stepMinutes = 15
    /// 12h a day is plenty; iOS slows down with very many events per schedule.
    public static let maxMinutes = 12 * 60
    /// Everything the user picks is reported under one label. App names never leave the device.
    public static let label = "social"

    public static var all: [Int] { Array(stride(from: stepMinutes, through: maxMinutes, by: stepMinutes)) }

    private static let prefix = "bucket."

    /// DeviceActivityEvent.Name raw value for a bucket.
    public static func eventName(minutes: Int) -> String { "\(prefix)\(minutes)" }

    /// The bucket an event name stands for, or nil for anything else.
    public static func minutes(fromEventName name: String) -> Int? {
        guard name.hasPrefix(prefix), let m = Int(name.dropFirst(prefix.count)),
              m > 0, m % stepMinutes == 0 else { return nil }
        return m
    }

    /// Threshold for a bucket, split into hours and minutes.
    public static func threshold(minutes: Int) -> DateComponents {
        DateComponents(hour: minutes / 60, minute: minutes % 60)
    }

    /// False when a callback can't be real: reaching N minutes takes N minutes since local midnight.
    /// Guards against iOS firing thresholds early, which some iOS 17 builds do right after monitoring starts.
    public static func isPlausible(minutes: Int, at date: Date, calendar: Calendar) -> Bool {
        date.timeIntervalSince(calendar.startOfDay(for: date)) >= TimeInterval(minutes * 60)
    }
}
