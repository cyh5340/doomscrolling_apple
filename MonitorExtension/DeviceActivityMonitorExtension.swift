import Auth
import DeviceActivity
import DoomscrollKit
import Foundation

/// Runs in its own process whenever today's usage of the picked apps crosses a 15-minute bucket.
/// Records the bucket in the shared outbox and uploads it straight away, so friends hear about it within minutes.
/// Keep this small: iOS kills monitor extensions that use more than ~6 MB.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let settings = SharedSettings.shared

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        let now = Date()
        settings.lastCallbackAt = now
        guard let minutes = Buckets.minutes(fromEventName: event.rawValue),
              Buckets.isPlausible(minutes: minutes, at: now, calendar: .current) else { return }
        OutboxStore.shared.recordBucket(minutes: minutes, at: now, calendar: .current)
        uploadBlocking()
    }

    /// A new day: a chance to send anything left over from yesterday.
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        uploadBlocking()
    }

    /// The extension can be suspended as soon as a callback returns, so wait (briefly) for the upload.
    private func uploadBlocking() {
        let done = DispatchSemaphore(value: 0)
        Task.detached { [settings] in
            do {
                try await EventUploader().upload(auth: SharedAuth.credentials)
                settings.lastUploadError = nil
            } catch {
                // Left pending: the next callback or the app retries.
                settings.lastUploadError = String(describing: error)
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 20)
    }
}

/// The app's Supabase session, read from the Keychain access group the app writes it to.
enum SharedAuth {
    static let client = AuthClient(
        configuration: AuthClient.Configuration(
            url: AppConfig.supabaseURL.appendingPathComponent("auth/v1"),
            headers: ["apikey": AppConfig.supabaseKey],
            storageKey: AppConfig.authStorageKey,
            localStorage: KeychainLocalStorage(accessGroup: AppConfig.appGroup),
            autoRefreshToken: false
        )
    )

    /// Refreshes the token if it expired; the refreshed session is saved back where the app reads it.
    @Sendable static func credentials() async throws -> (userId: String, accessToken: String) {
        let session = try await client.session
        return (session.user.id.uuidString.lowercased(), session.accessToken)
    }
}
