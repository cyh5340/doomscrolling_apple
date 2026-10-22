import DoomscrollKit
import SwiftUI

/// What the tracking pipeline is doing: Screen Time access, the monitoring schedule, extension callbacks and the
/// outbox. Compare "Friends see" with Settings › Screen Time over a normal day on a real phone.
struct DebugView: View {
    @State private var tracking = Tracking.shared
    @State private var events: [OutboxEvent] = []
    @State private var lastRun: Date?
    @State private var uploadOK: Bool?
    private let settings = SharedSettings.shared

    var body: some View {
        Screen(title: "Debug") {
            HStack(spacing: 12) {
                Button("Run now") { Task { await run() } }.buttonStyle(.borderedProminent)
                Button("Restart monitoring") {
                    try? tracking.start()
                    Task { await run() }
                }
                .buttonStyle(.bordered)
            }

            SectionHeader("Status")
            mono("Screen Time access: \(tracking.authorized ? "approved" : "not approved")")
            mono("Picked: \(tracking.selection.categoryTokens.count) categories, "
                 + "\(tracking.selection.applicationTokens.count) apps, \(tracking.selection.webDomainTokens.count) sites")
            mono("Monitoring: \(tracking.isMonitoring ? "on" : "off") (\(Buckets.all.count) buckets)")
            mono("Friends see today: \(formatMinutes(tracking.todayBucketMinutes))")
            mono("Last extension callback: \(settings.lastCallbackAt.map(time) ?? "—")")
            mono("Last extension upload error: \(settings.lastUploadError ?? "none")")
            mono("Last run: \(lastRun.map(time) ?? "—")\(uploadOK.map { $0 ? ", uploaded" : ", upload failed" } ?? "")")
            mono("Push: \(Push.isConfigured ? "configured" : "no GoogleService-Info.plist")")
            mono("Server: \(AppConfig.supabaseURL.absoluteString)")

            SectionHeader("Outbox (\(events.count))")
            ForEach(events) { e in mono("\(e.localDate) \(e.type) \(e.label) \(e.bucketMinutes)m  [\(e.status)]") }
        }
        .task { await run() }
    }

    private func run() async {
        tracking.refreshStatus()
        uploadOK = await tracking.upload()
        lastRun = .now
        events = OutboxStore.shared.all()
    }

    private func time(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .standard) }

    private func mono(_ text: String) -> some View {
        Text(text).font(.caption.monospaced()).foregroundStyle(Brand.onSurface).textSelection(.enabled)
    }
}
