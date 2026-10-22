import DoomscrollKit
import SwiftUI

struct GroupView: View {
    let groupId: String
    @Environment(Router.self) private var router
    @State private var group: FriendGroup?
    @State private var muted = false
    @State private var error = false
    @State private var pot: Pot?
    @State private var history: [(Settlement, String)] = []
    @State private var confirmLeave = false

    var body: some View {
        Screen(title: group?.name ?? "") {
            if error { Notice("Something went wrong. Check your connection.") }
            if let g = group {
                FlowLayout {
                    ForEach(rules(daily: g.dailyAlertMinutes, session: g.sessionAlertMinutes, streak: g.streakDays),
                            id: \.self) { Pill(text: $0) }
                    if g.stakeCents > 0 { Pill(text: "💸 \(formatMoney(g.stakeCents)) a week") }
                }

                if let pot { PotCard(pot: pot, history: history, me: Account.userId) }

                LeaderboardView(groupId: g.id, ranking: g.ranking).card()

                invite(g)

                Toggle(isOn: Binding(get: { muted }, set: { setMuted($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mute alerts")
                        Text("Stop notifications when someone here passes a limit.")
                            .font(.subheadline)
                            .foregroundStyle(Brand.onSurfaceVariant)
                    }
                }
                .padding(.vertical, 8)

                Button("Leave group", role: .destructive) { confirmLeave = true }
                    .foregroundStyle(Brand.error)
            } else if !error {
                ProgressView().frame(maxWidth: .infinity).padding(48)
            }
        }
        .toolbar {
            if let g = group {
                ShareLink(item: g.inviteLink, message: Text(inviteMessage(g)))
            }
        }
        .alert("Leave \(group?.name ?? "")?", isPresented: $confirmLeave) {
            Button("Leave", role: .destructive, action: leave)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need a new invite to come back."
                 + ((group?.stakeCents ?? 0) > 0 ? " You're still in this week's pot, and past weeks still count." : ""))
        }
        .task { await load() }
    }

    private func invite(_ g: FriendGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invite friends").font(.title2.weight(.semibold))
            Text(g.stakeCents > 0
                 ? "Friends see these rules and the \(formatMoney(g.stakeCents)) stake before they join."
                 : "Anyone with the link joins with these rules. Nothing to set up.")
                .font(.subheadline)
            HStack(spacing: 12) {
                Text("Code").font(.subheadline.weight(.semibold))
                Text(g.inviteCode).font(.headline.monospaced()).textSelection(.enabled)
            }
            ShareLink(item: g.inviteLink, message: Text(inviteMessage(g))) {
                Label("Share invite link", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(BigButtonStyle())
        }
        .foregroundStyle(Brand.onPrimaryContainer)
        .card(Brand.primaryContainer)
    }

    private func inviteMessage(_ g: FriendGroup) -> String { "Join my Doomscroll group \"\(g.name)\": \(g.inviteLink)" }

    private func load() async {
        do {
            let g = try await Groups.get(groupId)
            group = g
            muted = try await Groups.isMuted(groupId: groupId)
            if g.stakeCents > 0 {
                // ponytail: loaded once per visit; the leaderboard below is the live view.
                pot = try await Groups.pot(groupId: groupId, weekStart: weekStart(.now))
                history = try await Groups.settlements(groupId: groupId)
            }
        } catch {
            self.error = true
        }
    }

    private func setMuted(_ value: Bool) {
        muted = value
        Task {
            do { try await Groups.setMuted(groupId: groupId, value) } catch { muted = !value }
        }
    }

    private func leave() {
        Task {
            do {
                try await Groups.leave(groupId: groupId)
                router.path = []
            } catch {
                self.error = true
            }
        }
    }
}

private struct PotCard: View {
    let pot: Pot
    let history: [(Settlement, String)]
    let me: String?

    var body: some View {
        let stake = formatMoney(pot.stakeCents)
        let others = pot.members - 1
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                EmojiBadge(emoji: "💸")
                VStack(alignment: .leading) {
                    Text("This week's pot").font(.title2.weight(.semibold))
                    Text("Settles Monday").font(.caption).foregroundStyle(Brand.onSurfaceVariant)
                }
                Spacer()
                Text(stake).font(.title.weight(.semibold)).foregroundStyle(Brand.primary)
            }

            // Who's on the hook if the week ended now.
            let (text, tone): (String, Color) = if others < 1 {
                ("The pot starts once two people have been in the group since Monday.", Brand.onSurfaceVariant)
            } else if !pot.youIn {
                ("You're in the pot from next Monday. This week is between the others.", Brand.onSurfaceVariant)
            } else if pot.leaderId == nil {
                ("Nobody's on the hook yet. Ties don't pay.", Brand.tertiary)
            } else if pot.leaderId == me {
                ("You're on the hook. Put the phone down.", Brand.error)
            } else {
                ("\(pot.leaderName ?? "Someone") is on the hook right now.", Brand.primary)
            }
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(tone)

            if others >= 1 {
                HStack(spacing: 8) {
                    figure("Paid in", stake)
                    figure("Processing fee", formatMoney(pot.feeCents))
                    figure(others == 1 ? "The other gets" : "Each of \(others) gets", formatMoney(pot.shareCents))
                }
            }

            if !history.isEmpty {
                Divider()
                Text("Past weeks").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.onSurfaceVariant)
                ForEach(history, id: \.0.id) { s, name in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("\(s.loserId == me ? "You" : name) owed \(formatMoney(s.stakeCents))").font(.subheadline)
                            Text("Week of \(weekLabel(s.weekStart)) · \(formatMoney(s.shareCents)) each")
                                .font(.caption)
                                .foregroundStyle(Brand.onSurfaceVariant)
                        }
                        Spacer()
                        if s.paidAt != nil {
                            Pill(text: "Paid", container: Brand.tertiaryContainer, content: Brand.onTertiaryContainer)
                        } else {
                            Pill(text: "Due", container: Brand.errorContainer, content: Brand.onErrorContainer)
                        }
                    }
                }
            }
        }
        .foregroundStyle(Brand.onSurface)
        .card()
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(Brand.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Brand.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 16))
    }

    private func weekLabel(_ day: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: day) else { return day }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
