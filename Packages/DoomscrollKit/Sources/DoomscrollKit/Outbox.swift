import Foundation

/// One row in shared/contracts/events.schema.json (in the Android repo), minus userId/platform, which are
/// added at upload. The unique `dedupeKey` records what was already emitted, so sent rows are kept a while.
public struct OutboxEvent: Codable, Equatable, Identifiable, Sendable {
    public static let pending = "pending"
    public static let sent = "sent"

    public var eventId: String
    public var dedupeKey: String
    public var label: String
    public var type: String
    public var bucketMinutes: Int
    public var localDate: String
    public var timezone: String
    public var occurredAt: String
    public var status: String

    public var id: String { eventId }
}

/// The event outbox, a JSON file in the App Group container. Written by the monitor extension when a bucket is
/// reached and by the app after uploading, so every access is file-coordinated across processes.
// ponytail: whole-file JSON rewrite; fine for a few hundred rows a week. Move to SQLite if it grows.
public final class OutboxStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    /// Sent rows are only needed to stop re-emitting today's buckets, so they're dropped after this many days.
    private let keepSentDays = 7

    public init(url: URL) {
        self.url = url
    }

    /// The outbox shared by the app and its extensions.
    public static let shared = OutboxStore(url: SharedContainer.url.appendingPathComponent("outbox.json"))

    /// Records that today's usage for `label` reached `minutes`. Returns the new event, or nil if this bucket was
    /// already recorded today (iOS repeats callbacks when monitoring restarts).
    @discardableResult
    public func recordBucket(minutes: Int, label: String = Buckets.label, at date: Date, calendar: Calendar) -> OutboxEvent? {
        let day = Self.localDate(date, calendar: calendar)
        let key = "bucket:\(day):\(label):\(minutes)"
        var created: OutboxEvent?
        update { events in
            guard !events.contains(where: { $0.dedupeKey == key }) else { return }
            let event = OutboxEvent(
                eventId: UUID().uuidString.lowercased(),
                dedupeKey: key,
                label: label,
                type: "bucket_reached",
                bucketMinutes: minutes,
                localDate: day,
                timezone: calendar.timeZone.identifier,
                occurredAt: Self.iso.string(from: date),
                status: OutboxEvent.pending
            )
            events.append(event)
            created = event
        }
        return created
    }

    /// Every row, newest first.
    public func all() -> [OutboxEvent] {
        read().sorted { $0.occurredAt > $1.occurredAt }
    }

    public func pending(limit: Int = 500) -> [OutboxEvent] {
        Array(read().filter { $0.status == OutboxEvent.pending }.sorted { $0.occurredAt < $1.occurredAt }.prefix(limit))
    }

    public func markSent(_ ids: [String], now: Date = Date(), calendar: Calendar = .current) {
        let ids = Set(ids)
        let cutoff = Self.localDate(calendar.date(byAdding: .day, value: -keepSentDays, to: now) ?? now, calendar: calendar)
        update { events in
            for i in events.indices where ids.contains(events[i].eventId) {
                events[i].status = OutboxEvent.sent
            }
            events.removeAll { $0.status == OutboxEvent.sent && $0.localDate < cutoff }
        }
    }

    /// Highest bucket reached today for `label`: what friends see. Exact minutes are only in the report extension.
    public func todayMinutes(label: String = Buckets.label, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = Self.localDate(now, calendar: calendar)
        return read().filter { $0.label == label && $0.localDate == today }.map(\.bucketMinutes).max() ?? 0
    }

    /// When the oldest event still waiting to upload happened, or nil.
    public func oldestPending() -> Date? {
        pending(limit: 1).first.flatMap { Self.iso.date(from: $0.occurredAt) }
    }

    public func clear() {
        update { $0.removeAll() }
    }

    // MARK: - File access

    private func read() -> [OutboxEvent] {
        lock.lock()
        defer { lock.unlock() }
        var result: [OutboxEvent] = []
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { url in
            result = Self.decode(url)
        }
        return result
    }

    private func update(_ change: (inout [OutboxEvent]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &error) { url in
            var events = Self.decode(url)
            change(&events)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(events).write(to: url, options: .atomic)
        }
    }

    private static func decode(_ url: URL) -> [OutboxEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([OutboxEvent].self, from: data)) ?? []
    }

    // MARK: - Formats

    nonisolated(unsafe) static let iso = ISO8601DateFormatter()

    /// yyyy-MM-dd in the calendar's time zone.
    public static func localDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
