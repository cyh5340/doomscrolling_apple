import DoomscrollKit
import SwiftUI

struct NewGroupView: View {
    @Environment(Router.self) private var router
    @State private var name = ""
    @State private var preset = Preset.all[0]
    @State private var leastWins = false
    @State private var stakeCents = 2000
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Screen(title: "New group") {
            if let error { Notice(error) }
            TextField("Group name", text: $name)
                .padding(16)
                .background(Brand.surfaceContainer, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: name) { _, new in if new.count > 60 { name = String(new.prefix(60)) } }

            SectionHeader("Alert the group when someone passes")
            ForEach(Preset.all, id: \.self) { p in
                Button { preset = p } label: {
                    HStack(spacing: 12) {
                        Image(systemName: p == preset ? "largecircle.fill.circle" : "circle")
                            .font(.title3)
                            .foregroundStyle(p == preset ? Brand.primary : Brand.onSurfaceVariant)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.headline)
                            Text(rules(daily: p.dailyAlertMinutes, session: p.sessionAlertMinutes, streak: p.streakDays)
                                .joined(separator: "  "))
                                .font(.caption)
                                .foregroundStyle(Brand.onSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(p == preset ? Brand.primary : Brand.outlineVariant, lineWidth: p == preset ? 2 : 1)
                    }
                }
                .buttonStyle(.plain)
            }
            Text("Session alerts come from friends on Android. iPhones can only report daily time, not single sessions.")
                .font(.caption)
                .foregroundStyle(Brand.onSurfaceVariant)

            SectionHeader("Leaderboard")
            Picker("Leaderboard", selection: $leastWins) {
                Text("Most scrolled first").tag(false)
                Text("Least wins").tag(true)
            }
            .pickerStyle(.segmented)

            SectionHeader("Weekly stake")
            FlowLayout {
                ForEach([0, 500, 1000, 2000, 5000], id: \.self) { cents in
                    let selected = stakeCents == cents
                    Button { stakeCents = cents } label: {
                        Pill(text: cents == 0 ? "No stake" : formatMoney(cents),
                             container: selected ? Brand.secondaryContainer : Brand.surfaceContainerHigh,
                             content: selected ? Brand.onSurface : Brand.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(stakeCents == 0
                 ? "Just bragging rights. You can't add a stake later."
                 : "Whoever scrolls the most each week pays \(formatMoney(stakeCents)) into the pot. After a processing "
                    + "fee, it's split evenly among everyone else. Friends agree to it when they join, and it can't be "
                    + "changed later.")
                .font(.caption)
                .foregroundStyle(Brand.onSurfaceVariant)

            Button("Create group", action: create)
                .buttonStyle(BigButtonStyle())
                .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)

            HStack {
                Rectangle().fill(Brand.outlineVariant).frame(height: 1)
                Text("or").foregroundStyle(Brand.onSurfaceVariant).padding(.horizontal, 16)
                Rectangle().fill(Brand.outlineVariant).frame(height: 1)
            }
            .padding(.vertical, 8)

            SectionHeader("Join a friend's group")
            TextField("Invite link or code", text: $code)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(16)
                .background(Brand.surfaceContainer, in: RoundedRectangle(cornerRadius: 12))
            Button("Join") { router.path.append(.join(inviteCode(code))) }
                .buttonStyle(BigButtonStyle(filled: false))
                .disabled(inviteCode(code).isEmpty)
        }
    }

    private func create() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let group = try await Groups.create(name: name.trimmingCharacters(in: .whitespaces), preset: preset,
                                                    ranking: leastWins ? "least" : "most", stakeCents: stakeCents)
                router.path = [.group(group.id)]
            } catch {
                self.error = "Couldn't create the group."
            }
        }
    }
}
