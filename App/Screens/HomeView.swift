@preconcurrency import DeviceActivity
import DoomscrollKit
import FamilyControls
import SwiftUI

extension DeviceActivityReport.Context {
    /// Drawn by the report extension (ReportExtension/TodayReport.swift).
    static let today = Self("today")
}

struct HomeView: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var tracking = Tracking.shared
    @State private var groups: [FriendGroup]?
    @State private var groupsFailed = false
    @State private var stalled = false
    @State private var bucketMinutes = 0
    @State private var confirmDelete = false
    @State private var deleteFailed = false
    @State private var picking = false
    @State private var selection = FamilyActivitySelection()

    var body: some View {
        Screen(title: "Today") {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.body)
                .foregroundStyle(Brand.onSurfaceVariant)
                .padding(.top, -12)

            if !tracking.authorized {
                Notice("Tracking is paused: Screen Time access was turned off.", action: "Turn it back on") {
                    Task {
                        try? await tracking.requestAuthorization()
                        tracking.ensureMonitoring()
                    }
                }
            } else if !tracking.hasSelection {
                Notice("Pick the apps to track, or nothing is measured.", action: "Choose apps") { pickApps() }
            }
            if stalled {
                Notice("Some updates haven't reached your friends yet. Check your connection.", action: "Try again") {
                    Task { await refresh() }
                }
            }
            if deleteFailed { Notice("Couldn't delete your account. Check your connection and try again.") }

            today

            SectionHeader("Your groups")
            if let groups {
                if groups.isEmpty {
                    emptyGroups
                } else {
                    ForEach(groups) { group in
                        NavigationLink(value: Route.group(group.id)) { GroupCard(group: group) }
                            .buttonStyle(.plain)
                    }
                }
            } else if groupsFailed {
                Notice("Couldn't load your groups. Check your connection.")
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(24)
            }
        }
        .toolbar {
            Menu {
                Button("Change tracked apps", systemImage: "apps.iphone") { pickApps() }
                NavigationLink(value: Route.debug) { Label("Debug", systemImage: "ladybug") }
                Button("Delete account", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                NavigationLink(value: Route.newGroup) {
                    Label("Create or join", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .frame(height: 56)
                        .foregroundStyle(Brand.onPrimaryContainer)
                        .background(Brand.primaryContainer, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .familyActivityPicker(isPresented: $picking, selection: $selection)
        .onChange(of: picking) { _, open in
            if !open, selection != tracking.selection { tracking.setSelection(selection) }
        }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete everything", role: .destructive) {
                Task {
                    do {
                        try await Account.delete()
                        router.reset()
                    } catch {
                        deleteFailed = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your account and all your data on our server and on this phone. It can't be undone.")
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    @ViewBuilder private var today: some View {
        let limit = groups?.map(\.dailyAlertMinutes).min()
        Group {
            if tracking.authorized && tracking.hasSelection {
                // Exact minutes, drawn by the report extension. The app never sees the number.
                DeviceActivityReport(.today, filter: tracking.todayFilter)
                    .frame(height: 390)
                    .id(limit) // redraw when the limit it reads from shared settings changes
            } else {
                TodayRing(minutes: bucketMinutes, limit: limit, exact: false)
            }
        }
        .background(Brand.surfaceContainer, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var emptyGroups: some View {
        VStack(spacing: 12) {
            EmojiBadge(emoji: "👯", size: 56)
            Text("Scrolling is easier to quit together").font(.headline).multilineTextAlignment(.center)
            Text("Start a group, invite friends, and you'll hear about it when someone overdoes it.")
                .font(.subheadline)
                .foregroundStyle(Brand.onSurfaceVariant)
                .multilineTextAlignment(.center)
            NavigationLink("Start a group", value: Route.newGroup).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .card(radius: 16, padding: 24)
    }

    private func pickApps() {
        selection = tracking.selection
        picking = true
    }

    private func refresh() async {
        tracking.ensureMonitoring()
        await tracking.upload()
        bucketMinutes = tracking.todayBucketMinutes
        // Events waiting over 2h to upload: the extension can't reach the server.
        stalled = OutboxStore.shared.oldestPending().map { Date.now.timeIntervalSince($0) >= 2 * 3600 } ?? false
        do {
            groups = try await Groups.mine()
            groupsFailed = false
        } catch {
            groupsFailed = true
        }
    }
}

private struct GroupCard: View {
    let group: FriendGroup

    var body: some View {
        HStack(spacing: 16) {
            Avatar(name: group.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.headline)
                Text(summary).font(.subheadline).foregroundStyle(Brand.onSurfaceVariant)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Brand.onSurfaceVariant)
        }
        .foregroundStyle(Brand.onSurface)
        .card(radius: 16, padding: 16)
        .contentShape(Rectangle())
    }

    private var summary: String {
        var s = "\(formatMinutes(group.dailyAlertMinutes)) a day"
        if let session = group.sessionAlertMinutes { s += " · \(formatMinutes(session)) session" }
        if group.stakeCents > 0 { s += " · \(formatMoney(group.stakeCents))/week" }
        s += group.ranking == "least" ? " · hall of fame" : " · leaderboard"
        return s
    }
}
