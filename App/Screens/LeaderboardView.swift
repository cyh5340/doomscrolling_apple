import DoomscrollKit
import SwiftUI

private enum Period: String, CaseIterable, Identifiable {
    case day = "Today", week = "This week"
    var id: Self { self }

    func range(_ today: Date = .now) -> (Date, Date) {
        switch self {
        case .day: (today, today)
        case .week: (weekStart(today), today)
        }
    }
}

/// Live leaderboard for a group. `ranking` is the group setting: "most" = most doomscrolled first,
/// "least" = hall of fame.
struct LeaderboardView: View {
    let groupId: String
    let ranking: String
    @State private var period = Period.day
    @State private var rows: [LeaderboardRow]?
    @State private var failed = false

    private var least: Bool { ranking == "least" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(least ? "Hall of fame" : "Most doomscrolled").font(.title2.weight(.semibold))
                Text(least ? "Least time in social apps wins." : "Top spot is not the one you want.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.onSurfaceVariant)
            }
            Picker("Period", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if failed {
                Text("Couldn't load the leaderboard.").foregroundStyle(Brand.error)
            } else if let rows {
                if rows.isEmpty {
                    Text("Nobody here yet.").foregroundStyle(Brand.onSurfaceVariant)
                } else {
                    let sorted = least ? rows.sorted { $0.minutes < $1.minutes } : rows
                    let top = max(rows.map(\.minutes).max() ?? 1, 1)
                    VStack(spacing: 4) {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { i, row in
                            MemberRow(rank: i + 1, row: row, isMe: row.userId == Account.userId,
                                      share: Double(row.minutes) / Double(top), least: least)
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(24)
            }
        }
        .foregroundStyle(Brand.onSurface)
        .task(id: period) {
            rows = nil
            failed = false
            let (from, to) = period.range()
            do {
                for try await update in Groups.leaderboard(groupId: groupId, from: from, to: to) { rows = update }
            } catch {
                failed = true
            }
        }
    }
}

private let medals: [UInt32] = [0xF5B83D, 0xC3CAD6, 0xD08A5A]

private struct MemberRow: View {
    let rank: Int
    let row: LeaderboardRow
    let isMe: Bool
    let share: Double
    let least: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(rank <= medals.count ? Brand.ink : Brand.onSurfaceVariant)
                .frame(width: 26, height: 26)
                .background(rank <= medals.count ? Color(rgb: medals[rank - 1]) : .clear, in: Circle())
            // ponytail: initials avatar; load photo_url once Sign in with Apple exists.
            Avatar(name: row.displayName)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(row.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if isMe {
                        Text("YOU")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Brand.onSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Brand.secondary, in: Capsule())
                    }
                }
                // Bar relative to the group's top scroller.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Brand.surfaceContainerHighest)
                        Capsule().fill(least ? Brand.tertiary : Brand.primary).frame(width: geo.size.width * share)
                    }
                }
                .frame(height: 6)
            }
            VStack(alignment: .trailing) {
                Text(formatMinutes(row.minutes)).font(.subheadline.weight(.semibold))
                if row.streak > 0 {
                    Text("🔥 \(row.streak)").font(.caption.weight(.semibold)).foregroundStyle(Brand.primary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isMe ? Brand.secondaryContainer.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 16))
    }
}
