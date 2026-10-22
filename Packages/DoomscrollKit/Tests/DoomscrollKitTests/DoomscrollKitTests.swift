import Foundation
import Testing
@testable import DoomscrollKit

let zone = TimeZone(identifier: "America/Los_Angeles")!
let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = zone
    return c
}()

/// A local time on 2026-10-18 (or `day`).
func t(_ h: Int, _ m: Int = 0, day: Int = 18) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
}

func tempOutbox() -> OutboxStore {
    OutboxStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID()).json"))
}

@Suite struct BucketsTests {
    @Test func everyFifteenMinutesUpToTwelveHours() {
        #expect(Buckets.all.first == 15)
        #expect(Buckets.all.last == 720)
        #expect(Buckets.all.count == 48)
    }

    @Test func eventNamesRoundTrip() {
        for m in Buckets.all { #expect(Buckets.minutes(fromEventName: Buckets.eventName(minutes: m)) == m) }
        #expect(Buckets.minutes(fromEventName: "bucket.7") == nil)
        #expect(Buckets.minutes(fromEventName: "bucket.") == nil)
        #expect(Buckets.minutes(fromEventName: "other.15") == nil)
    }

    @Test func thresholdSplitsHours() {
        #expect(Buckets.threshold(minutes: 75) == DateComponents(hour: 1, minute: 15))
        #expect(Buckets.threshold(minutes: 45) == DateComponents(hour: 0, minute: 45))
    }

    @Test func callbackBeforeTheBucketCouldBeReachedIsImplausible() {
        #expect(!Buckets.isPlausible(minutes: 60, at: t(0, 30), calendar: calendar))
        #expect(Buckets.isPlausible(minutes: 60, at: t(1), calendar: calendar))
    }
}

@Suite struct OutboxTests {
    @Test func recordsBucketWithContractFields() throws {
        let outbox = tempOutbox()
        let e = try #require(outbox.recordBucket(minutes: 45, at: t(10, 5), calendar: calendar))
        #expect(e.type == "bucket_reached")
        #expect(e.label == "social")
        #expect(e.localDate == "2026-10-18")
        #expect(e.timezone == "America/Los_Angeles")
        #expect(e.occurredAt == "2026-10-18T17:05:00Z")
        #expect(e.status == OutboxEvent.pending)
        #expect(UUID(uuidString: e.eventId) != nil)
    }

    @Test func sameBucketSameDayIsRecordedOnce() {
        let outbox = tempOutbox()
        #expect(outbox.recordBucket(minutes: 15, at: t(10), calendar: calendar) != nil)
        #expect(outbox.recordBucket(minutes: 15, at: t(11), calendar: calendar) == nil)
        #expect(outbox.recordBucket(minutes: 15, at: t(10, day: 19), calendar: calendar) != nil)
        #expect(outbox.all().count == 2)
    }

    @Test func localDateFollowsTheCalendarZone() {
        // 23:50 in Los Angeles is already the next day in UTC.
        let e = tempOutbox().recordBucket(minutes: 15, at: t(23, 50), calendar: calendar)
        #expect(e?.localDate == "2026-10-18")
    }

    @Test func markSentKeepsRecentKeysSoTheyStayDeduplicated() {
        let outbox = tempOutbox()
        let e = outbox.recordBucket(minutes: 15, at: t(10), calendar: calendar)!
        outbox.markSent([e.eventId], now: t(12), calendar: calendar)
        #expect(outbox.pending().isEmpty)
        #expect(outbox.recordBucket(minutes: 15, at: t(13), calendar: calendar) == nil)
    }

    @Test func oldSentRowsArePruned() {
        let outbox = tempOutbox()
        let old = outbox.recordBucket(minutes: 15, at: t(10, day: 1), calendar: calendar)!
        let stillPending = outbox.recordBucket(minutes: 30, at: t(10, day: 2), calendar: calendar)!
        outbox.markSent([old.eventId], now: t(12), calendar: calendar)
        #expect(outbox.all().map(\.eventId) == [stillPending.eventId])
    }

    @Test func pendingIsOldestFirst() {
        let outbox = tempOutbox()
        outbox.recordBucket(minutes: 30, at: t(11), calendar: calendar)
        outbox.recordBucket(minutes: 15, at: t(10), calendar: calendar)
        #expect(outbox.pending().map(\.bucketMinutes) == [15, 30])
        #expect(outbox.oldestPending() == t(10))
    }

    @Test func todayMinutesIsTheHighestBucketToday() {
        let outbox = tempOutbox()
        outbox.recordBucket(minutes: 90, at: t(20, day: 17), calendar: calendar)
        outbox.recordBucket(minutes: 15, at: t(10), calendar: calendar)
        outbox.recordBucket(minutes: 30, at: t(11), calendar: calendar)
        #expect(outbox.todayMinutes(now: t(12), calendar: calendar) == 30)
        #expect(outbox.todayMinutes(now: t(12, day: 19), calendar: calendar) == 0)
    }
}

@Suite struct UploaderTests {
    @Test func requestMatchesTheEventsTable() throws {
        let outbox = tempOutbox()
        let e = outbox.recordBucket(minutes: 45, at: t(10), calendar: calendar)!
        let uploader = EventUploader(outbox: outbox, baseURL: URL(string: "https://x.supabase.co")!, apiKey: "key")
        let request = try uploader.request([e], userId: "u1", accessToken: "tok")

        #expect(request.url?.absoluteString == "https://x.supabase.co/rest/v1/events?on_conflict=event_id")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "apikey") == "key")
        #expect(request.value(forHTTPHeaderField: "Prefer")?.contains("resolution=ignore-duplicates") == true)

        let rows = try JSONSerialization.jsonObject(with: request.httpBody!) as! [[String: Any]]
        #expect(Set(rows[0].keys) == ["event_id", "user_id", "platform", "label", "type", "bucket_minutes", "local_date",
                                      "timezone", "occurred_at"])
        #expect(rows[0]["platform"] as? String == "ios")
        #expect(rows[0]["user_id"] as? String == "u1")
        #expect(rows[0]["bucket_minutes"] as? Int == 45)
    }
}

@Suite struct FormatTests {
    @Test func minutes() {
        #expect(formatMinutes(45) == "45 min")
        #expect(formatMinutes(60) == "1h")
        #expect(formatMinutes(75) == "1h 15m")
    }

    @Test func money() {
        #expect(formatMoney(2000) == "$20")
        #expect(formatMoney(1805) == "$18.05")
    }

    @Test func takesTheCodeFromABareCodeOrAnyShapeOfLink() {
        #expect(inviteCode("abc123") == "abc123")
        #expect(inviteCode("  abc123 \n") == "abc123")
        #expect(inviteCode("https://doomscroll.app/join/abc123") == "abc123")
        #expect(inviteCode("https://doomscroll.app/join/abc123/") == "abc123")
        #expect(inviteCode("https://doomscroll.app/join/abc123?utm_source=x#top") == "abc123")
        #expect(inviteCode("   ") == "")
        #expect(inviteCode("/") == "")
    }

    @Test func inviteLinks() {
        #expect(inviteCode(from: URL(string: "https://doomscroll.app/join/abc123")!) == "abc123")
        #expect(inviteCode(from: URL(string: "https://doomscroll.app/join/")!) == nil)
        #expect(inviteCode(from: URL(string: "https://doomscroll.app/other/abc")!) == nil)
    }

    @Test func weeksStartOnMonday() {
        // 2026-10-18 is a Sunday; its week started Monday the 12th.
        #expect(weekStart(t(10), calendar: calendar) == t(0, day: 12))
        #expect(weekStart(t(0, day: 19), calendar: calendar) == t(0, day: 19))
    }
}
