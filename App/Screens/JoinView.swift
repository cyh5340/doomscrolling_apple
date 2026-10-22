import DoomscrollKit
import SwiftUI

/// Invite landing page. Joining a staked group needs this screen, since tapping the button states the stake.
struct JoinView: View {
    let code: String
    @Environment(Router.self) private var router
    @State private var preview: GroupPreview?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        Screen(title: "Join group") {
            if let error { Notice(error) }
            if let p = preview {
                HStack(spacing: 16) {
                    Avatar(name: p.name, size: 56)
                    VStack(alignment: .leading) {
                        Text(p.name).font(.title2.weight(.semibold))
                        Text(p.members == 1 ? "1 member" : "\(p.members) members").foregroundStyle(Brand.onSurfaceVariant)
                    }
                }

                if p.stakeCents > 0 {
                    let stake = formatMoney(p.stakeCents)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(stake) weekly stake").font(.title2.weight(.semibold))
                        InfoRow(emoji: "💸", title: "If you scroll the most",
                                text: "You pay \(stake) into the pot for that week (Monday to Sunday).")
                        InfoRow(emoji: "🎁", title: "If someone else does",
                                text: "Their \(stake) is split evenly among everyone else, after a processing fee.")
                        InfoRow(emoji: "🤝", title: "Ties", text: "Nobody pays on a tie for the top spot.")
                    }
                    .card()
                }

                Button(p.stakeCents > 0 ? "Join and accept the \(formatMoney(p.stakeCents)) stake" : "Join group") {
                    join(p)
                }
                .buttonStyle(BigButtonStyle())
                .disabled(busy)
            } else if error == nil {
                ProgressView().frame(maxWidth: .infinity).padding(48)
            }
        }
        .task {
            do {
                preview = try await Groups.preview(code: code)
                if preview == nil { error = "This invite doesn't work anymore." }
            } catch {
                self.error = "Couldn't load the invite. Check your connection."
            }
        }
    }

    private func join(_ p: GroupPreview) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let id = try await Groups.join(code: code, acceptStake: p.stakeCents > 0)
                router.path = [.group(id)]
            } catch {
                self.error = "Couldn't join. Check your connection and try again."
            }
        }
    }
}
