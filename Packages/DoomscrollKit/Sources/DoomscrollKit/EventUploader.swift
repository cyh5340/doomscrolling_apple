import Foundation

/// Row in public.events; mirrors shared/contracts/events.schema.json.
struct EventRow: Encodable {
    let event_id: String
    let user_id: String
    let platform: String
    let label: String
    let type: String
    let bucket_minutes: Int
    let local_date: String
    let timezone: String
    let occurred_at: String

    init(_ e: OutboxEvent, userId: String) {
        event_id = e.eventId
        user_id = userId
        platform = "ios"
        label = e.label
        type = e.type
        bucket_minutes = e.bucketMinutes
        local_date = e.localDate
        timezone = e.timezone
        occurred_at = e.occurredAt
    }
}

public struct UploadError: Error, CustomStringConvertible {
    public let status: Int
    public let body: String
    public var description: String { "HTTP \(status): \(body)" }
}

/// Sends pending outbox rows straight to PostgREST with URLSession. No Supabase SDK, so the monitor extension
/// can use it too. The event id is the primary key and duplicates are ignored, so a resend is a no-op.
public struct EventUploader: Sendable {
    public let outbox: OutboxStore
    public let baseURL: URL
    public let apiKey: String
    public let session: URLSession

    public init(outbox: OutboxStore = .shared, baseURL: URL = AppConfig.supabaseURL, apiKey: String = AppConfig.supabaseKey,
                session: URLSession = .shared) {
        self.outbox = outbox
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    /// Uploads everything pending. `auth` returns the signed-in user's id and a valid access token.
    public func upload(auth: () async throws -> (userId: String, accessToken: String)) async throws {
        while true {
            let batch = outbox.pending()
            if batch.isEmpty { return }
            let (userId, token) = try await auth()
            try await send(batch, userId: userId, accessToken: token)
            outbox.markSent(batch.map(\.eventId))
        }
    }

    func request(_ batch: [OutboxEvent], userId: String, accessToken: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/events"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "event_id")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(batch.map { EventRow($0, userId: userId) })
        return request
    }

    private func send(_ batch: [OutboxEvent], userId: String, accessToken: String) async throws {
        let (data, response) = try await session.data(for: request(batch, userId: userId, accessToken: accessToken))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw UploadError(status: status, body: String(decoding: data, as: UTF8.self))
        }
    }
}
