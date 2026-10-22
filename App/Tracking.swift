@preconcurrency import DeviceActivity
import DoomscrollKit
import FamilyControls
import Foundation
import ManagedSettings
import Observation

extension DeviceActivityName {
    static let daily = Self("daily")
}

/// Screen Time access, the apps the user picked, and the daily monitoring schedule that drives the monitor
/// extension. iOS never tells the app how long anything was used: it only calls the extension at each
/// 15-minute bucket, which is exactly what friends are allowed to see.
@MainActor @Observable
final class Tracking {
    static let shared = Tracking()

    private(set) var authorized = false
    private(set) var selection = FamilyActivitySelection()
    private let settings = SharedSettings.shared
    private let center = DeviceActivityCenter()

    private init() {
        if let data = settings.selection, let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        }
        refreshStatus()
    }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    var isMonitoring: Bool { center.activities.contains(.daily) }

    func refreshStatus() {
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        refreshStatus()
    }

    /// Saves the picked apps and restarts monitoring with them.
    func setSelection(_ new: FamilyActivitySelection) {
        selection = new
        settings.selection = try? JSONEncoder().encode(new)
        try? start()
    }

    /// Starts (or restarts) the daily schedule with one event per bucket. Past usage today counts, so starting
    /// mid-day re-reports buckets already reached; the outbox drops the repeats.
    func start() throws {
        guard authorized, hasSelection else { return }
        let events = Dictionary(uniqueKeysWithValues: Buckets.all.map { minutes in
            (DeviceActivityEvent.Name(Buckets.eventName(minutes: minutes)), DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: Buckets.threshold(minutes: minutes),
                includesPastActivity: true
            ))
        })
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        center.stopMonitoring([.daily])
        try center.startMonitoring(.daily, during: schedule, events: events)
    }

    /// Starts monitoring if it isn't running, e.g. after a reinstall or an OS update.
    func ensureMonitoring() {
        refreshStatus()
        if !isMonitoring { try? start() }
    }

    func stop() {
        center.stopMonitoring()
    }

    /// Uploads whatever the extension couldn't send. Returns false if it failed.
    @discardableResult
    func upload() async -> Bool {
        do {
            try await EventUploader().upload(auth: Account.credentials)
            return true
        } catch {
            return false
        }
    }

    /// Today in 15-minute steps, as friends see it.
    var todayBucketMinutes: Int { OutboxStore.shared.todayMinutes() }

    /// Report filter for today's usage of the picked apps.
    var todayFilter: DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .daily(during: Calendar.current.dateInterval(of: .day, for: .now)!),
            users: .all,
            devices: .init([.iPhone, .iPad]),
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens
        )
    }
}
