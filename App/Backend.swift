import DoomscrollKit
import Foundation
import Supabase

/// The Supabase project the Android app uses too (backend/ in the Android repo). Clients only report events;
/// the server derives daily totals, alerts, streaks, leaderboards and the weekly stake.
let supabase = SupabaseClient(
    supabaseURL: AppConfig.supabaseURL,
    supabaseKey: AppConfig.supabaseKey,
    options: SupabaseClientOptions(
        auth: .init(
            // Shared with the monitor extension, which uploads with the same session.
            storage: KeychainLocalStorage(accessGroup: AppConfig.appGroup),
            storageKey: AppConfig.authStorageKey,
            emitLocalSessionAsInitialSession: true
        )
    )
)

// MARK: - Models

struct FriendGroup: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let ownerId: String
    let inviteCode: String
    let label: String
    let dailyAlertMinutes: Int
    let sessionAlertMinutes: Int?
    let streakDays: Int
    let ranking: String
    /// Weekly stake, paid by the group's top doomscroller. 0 = no stake.
    let stakeCents: Int

    var inviteLink: URL { URL(string: "https://\(AppConfig.inviteHost)/join/\(inviteCode)")! }

    enum CodingKeys: String, CodingKey {
        case id, name, label, ranking
        case ownerId = "owner_id", inviteCode = "invite_code", dailyAlertMinutes = "daily_alert_minutes"
        case sessionAlertMinutes = "session_alert_minutes", streakDays = "streak_days", stakeCents = "stake_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        ownerId = try c.decode(String.self, forKey: .ownerId)
        inviteCode = try c.decode(String.self, forKey: .inviteCode)
        label = try c.decode(String.self, forKey: .label)
        dailyAlertMinutes = try c.decode(Int.self, forKey: .dailyAlertMinutes)
        sessionAlertMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionAlertMinutes)
        streakDays = try c.decode(Int.self, forKey: .streakDays)
        ranking = try c.decode(String.self, forKey: .ranking)
        stakeCents = try c.decodeIfPresent(Int.self, forKey: .stakeCents) ?? 0
    }
}

struct LeaderboardRow: Decodable, Identifiable, Equatable {
    let userId: String
    let displayName: String
    let minutes: Int
    let streak: Int
    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case minutes, streak
        case userId = "user_id", displayName = "display_name"
    }
}

/// What an invite leads to, shown before joining so people agree to the stake.
struct GroupPreview: Decodable {
    let id: String
    let name: String
    let stakeCents: Int
    let members: Int

    enum CodingKeys: String, CodingKey {
        case id, name, members
        case stakeCents = "stake_cents"
    }
}

/// This week's pot. The server decides the fee, the split and who's on the hook (nil: nobody, or a tie).
/// `members` counts who's in this week's pot: people who joined mid-week start next Monday (`youIn` false).
struct Pot: Decodable {
    let stakeCents: Int
    let feeCents: Int
    let shareCents: Int
    let members: Int
    let leaderId: String?
    let leaderName: String?
    let youIn: Bool

    enum CodingKeys: String, CodingKey {
        case members
        case stakeCents = "stake_cents", feeCents = "fee_cents", shareCents = "share_cents"
        case leaderId = "leader_id", leaderName = "leader_name", youIn = "you_in"
    }
}

/// A settled week. Ledger only until payments exist: paidAt is set once the money is collected.
struct Settlement: Decodable, Identifiable {
    let weekStart: String
    let loserId: String?
    let stakeCents: Int
    let shareCents: Int
    let paidAt: String?
    var id: String { weekStart }

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start", loserId = "loser_id", stakeCents = "stake_cents", shareCents = "share_cents"
        case paidAt = "paid_at"
    }
}

struct Preset: Hashable {
    let name: String
    let dailyAlertMinutes: Int
    let sessionAlertMinutes: Int?
    let streakDays: Int

    static let all = [
        Preset(name: "Balanced", dailyAlertMinutes: 60, sessionAlertMinutes: 45, streakDays: 3),
        Preset(name: "Strict", dailyAlertMinutes: 30, sessionAlertMinutes: 15, streakDays: 3),
        Preset(name: "Relaxed", dailyAlertMinutes: 120, sessionAlertMinutes: nil, streakDays: 5),
    ]
}

/// Server dates are local calendar dates.
func isoDay(_ date: Date) -> String { OutboxStore.localDate(date, calendar: .current) }

// MARK: - Account

enum Account {
    static var userId: String? { supabase.auth.currentUser?.id.uuidString.lowercased() }

    // ponytail: anonymous accounts only; Sign in with Apple is a TODO (see TODO.md).
    static func signIn(displayName: String) async throws {
        if let uid = userId {
            try await supabase.from("profiles").update(["display_name": displayName]).eq("id", value: uid).execute()
        } else {
            try await supabase.auth.signInAnonymously(data: ["display_name": .string(displayName)])
        }
    }

    static func savePushToken(_ token: String) async throws {
        guard let uid = userId else { return }
        try await supabase.from("push_tokens").upsert(["user_id": uid, "token": token]).execute()
    }

    /// The signed-in user's id and a valid access token, for the event uploader.
    @Sendable static func credentials() async throws -> (userId: String, accessToken: String) {
        let session = try await supabase.auth.session
        return (session.user.id.uuidString.lowercased(), session.accessToken)
    }

    /// Deletes the account and all its data on the server, then everything local.
    static func delete() async throws {
        try await supabase.rpc("delete_account").execute()
        try? await supabase.auth.signOut(scope: .local)
        await Tracking.shared.stop()
        OutboxStore.shared.clear()
        SharedSettings.shared.clear()
    }
}

// MARK: - Groups

enum Groups {
    /// The user's groups. Also shares the strictest daily limit with the report extension's Today ring.
    static func mine() async throws -> [FriendGroup] {
        let groups: [FriendGroup] = try await supabase.from("groups").select().execute().value
        SharedSettings.shared.dailyLimitMinutes = groups.map(\.dailyAlertMinutes).min()
        return groups
    }

    static func get(_ id: String) async throws -> FriendGroup {
        try await supabase.from("groups").select().eq("id", value: id).single().execute().value
    }

    static func create(name: String, preset: Preset, ranking: String, stakeCents: Int) async throws -> FriendGroup {
        struct Params: Encodable {
            let name: String
            let daily_alert_minutes: Int
            let session_alert_minutes: Int?
            let streak_days: Int
            let ranking: String
            let stake_cents: Int
        }
        let group: FriendGroup = try await supabase.rpc("create_group", params: Params(
            name: name, daily_alert_minutes: preset.dailyAlertMinutes, session_alert_minutes: preset.sessionAlertMinutes,
            streak_days: preset.streakDays, ranking: ranking, stake_cents: stakeCents
        )).execute().value
        _ = try? await mine()
        return group
    }

    /// Nil when the code doesn't match a group.
    static func preview(code: String) async throws -> GroupPreview? {
        let rows: [GroupPreview] = try await supabase.rpc("group_preview", params: ["code": code]).execute().value
        return rows.first
    }

    /// Joins by invite code and returns the group id. `acceptStake` is the user's consent to the group's stake.
    static func join(code: String, acceptStake: Bool) async throws -> String {
        struct Params: Encodable {
            let code: String
            let accept_stake: Bool
        }
        let id: String = try await supabase.rpc("join_group", params: Params(code: code, accept_stake: acceptStake))
            .execute().value
        _ = try? await mine()
        return id
    }

    static func pot(groupId: String, weekStart: Date) async throws -> Pot? {
        let rows: [Pot] = try await supabase.rpc("pot", params: ["gid": groupId, "week_start": isoDay(weekStart)])
            .execute().value
        return rows.first
    }

    /// Recent settled weeks, newest first, with the name of who owed.
    static func settlements(groupId: String) async throws -> [(Settlement, String)] {
        struct ProfileName: Decodable {
            let id: String
            let display_name: String
        }
        let rows: [Settlement] = try await supabase.from("settlements").select().eq("group_id", value: groupId)
            .order("week_start", ascending: false).limit(8).execute().value
        let ids = Array(Set(rows.compactMap(\.loserId)))
        var names: [String: String] = [:]
        if !ids.isEmpty {
            let profiles: [ProfileName] = try await supabase.from("profiles").select("id, display_name")
                .in("id", values: ids).execute().value
            names = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.display_name) })
        }
        return rows.map { ($0, $0.loserId.flatMap { names[$0] } ?? "A former member") }
    }

    static func leave(groupId: String) async throws {
        guard let uid = Account.userId else { return }
        try await supabase.from("group_members").delete().eq("group_id", value: groupId).eq("user_id", value: uid).execute()
        _ = try? await mine()
    }

    static func isMuted(groupId: String) async throws -> Bool {
        struct Membership: Decodable { let muted: Bool }
        guard let uid = Account.userId else { return false }
        let m: Membership = try await supabase.from("group_members").select("muted").eq("group_id", value: groupId)
            .eq("user_id", value: uid).single().execute().value
        return m.muted
    }

    static func setMuted(groupId: String, _ muted: Bool) async throws {
        guard let uid = Account.userId else { return }
        try await supabase.from("group_members").update(["muted": muted]).eq("group_id", value: groupId)
            .eq("user_id", value: uid).execute()
    }

    static func fetchLeaderboard(groupId: String, from: Date, to: Date) async throws -> [LeaderboardRow] {
        try await supabase.rpc("leaderboard", params: ["gid": groupId, "from_date": isoDay(from), "to_date": isoDay(to)])
            .execute().value
    }

    /// Leaderboard rows, re-fetched live whenever a group-mate's daily usage changes. If Realtime can't connect,
    /// the first fetch still shows.
    static func leaderboard(groupId: String, from: Date, to: Date) -> AsyncThrowingStream<[LeaderboardRow], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let channel = supabase.channel("usage-\(UUID().uuidString)")
                // RLS limits these changes to the user and their group-mates.
                let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "daily_usage")
                do {
                    continuation.yield(try await fetchLeaderboard(groupId: groupId, from: from, to: to))
                    try await channel.subscribeWithError()
                    for await _ in changes {
                        continuation.yield(try await fetchLeaderboard(groupId: groupId, from: from, to: to))
                    }
                    continuation.finish()
                } catch is CancellationError {
                } catch {
                    continuation.finish(throwing: error)
                }
                await supabase.removeChannel(channel)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
