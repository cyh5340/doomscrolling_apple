import DoomscrollKit
import FamilyControls
import SwiftUI

private enum Step: Int { case disclosure, screenTime, apps, notifications, finishing }

struct OnboardingView: View {
    @Environment(Router.self) private var router
    @State private var step = Step.disclosure
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    @State private var picking = false
    @State private var selection = Tracking.shared.selection

    var body: some View {
        Group {
            switch step {
            case .disclosure: disclosure
            case .screenTime: screenTime
            case .apps: apps
            case .notifications: notifications
            case .finishing:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Setting things up…").foregroundStyle(Brand.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Brand.background)
        .foregroundStyle(Brand.onSurface)
        .animation(.default, value: step)
    }

    /// One onboarding step: progress bars on top, scrolling content, actions pinned to the bottom.
    private func page<Content: View, Bottom: View>(
        _ index: Int, @ViewBuilder content: () -> Content, @ViewBuilder bottom: () -> Bottom
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<4) { i in
                    Capsule().fill(i <= index ? Brand.primary : Brand.surfaceContainerHighest).frame(height: 4)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 24, content: content)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: 8, content: bottom)
        }
        .frame(maxWidth: maxContentWidth)
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private func heading(_ emoji: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            EmojiBadge(emoji: emoji, size: 72)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.largeTitle.weight(.semibold))
                Text(text).font(.body).foregroundStyle(Brand.onSurfaceVariant)
            }
        }
    }

    // MARK: Steps

    // Shown before any data is collected, with an explicit agree button (App Store guideline 5.1.1).
    private var disclosure: some View {
        page(0) {
            VStack(alignment: .leading, spacing: 8) {
                (Text("doom").foregroundColor(Brand.primary) + Text("scroll"))
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-0.5)
                Text("Keep each other honest about time spent scrolling.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Brand.onSurfaceVariant)
            }
            TextField("Your name, as friends will see it", text: $name)
                .textContentType(.givenName)
                .padding(16)
                .background(Brand.surfaceContainer, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: name) { _, new in if new.count > 40 { name = String(new.prefix(40)) } }
            InfoRow(emoji: "📱", title: "What this app tracks",
                    text: "How long you spend in the social apps you pick, such as TikTok, Instagram, YouTube, Reddit, X, "
                        + "Snapchat and Facebook. It uses Apple's Screen Time, which you allow in the next step.")
            InfoRow(emoji: "👀", title: "What your friends see",
                    text: "Only your time in 15-minute steps (for example \"social: 45 min\"), and an alert when you pass "
                        + "your group's limits. We'll ask to send you notifications when a friend passes theirs.")
            InfoRow(emoji: "🔒", title: "What never leaves your phone",
                    text: "Which apps you used, your exact minutes, and anything you do inside those apps. "
                        + "Apple doesn't even show those to Doomscroll.")
            InfoRow(emoji: "🗑️", title: "Your control",
                    text: "You can delete your account and all of its data at any time from the app.")
        } bottom: {
            if let error { Text(error).foregroundStyle(Brand.error).font(.subheadline) }
            Button(busy ? "Signing in…" : "I agree", action: agree)
                .buttonStyle(BigButtonStyle())
                .disabled(busy)
        }
    }

    private var screenTime: some View {
        page(1) {
            heading("📊", "Allow Screen Time access",
                    "This is how Doomscroll measures time in social apps. Apple asks you to confirm with Face ID or your "
                        + "passcode.")
            InfoRow(emoji: "🛡️", title: "Stays on your phone",
                    text: "iOS only tells Doomscroll each time you pass another 15 minutes. It never sees which app, or the "
                        + "exact time.")
            if let error { Text(error).foregroundStyle(Brand.error).font(.subheadline) }
        } bottom: {
            Button("Continue", action: authorize).buttonStyle(BigButtonStyle()).disabled(busy)
        }
    }

    private var apps: some View {
        page(2) {
            heading("📲", "Pick your doomscroll apps",
                    "Choose the Social category, plus YouTube or Reddit if they're your weak spot. Everything you pick "
                        + "counts as \"social\" for your group.")
            if hasSelection {
                Label(selectionSummary, systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Brand.tertiary)
            }
        } bottom: {
            if hasSelection {
                Button("Continue") {
                    Tracking.shared.setSelection(selection)
                    step = .notifications
                }
                .buttonStyle(BigButtonStyle())
                Button("Change apps") { picking = true }.buttonStyle(BigButtonStyle(filled: false))
            } else {
                Button("Choose apps") { picking = true }.buttonStyle(BigButtonStyle())
            }
        }
        .familyActivityPicker(isPresented: $picking, selection: $selection)
    }

    private var notifications: some View {
        page(3) {
            heading("🔔", "Friend alerts",
                    "Get a nudge when someone in your group passes their limit, so you can call them out.")
            // A sample of what an alert looks like.
            HStack(alignment: .top, spacing: 12) {
                EmojiBadge(emoji: "🔥", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DOOMSCROLL · now").font(.caption2.weight(.semibold)).foregroundStyle(Brand.onSurfaceVariant)
                    Text("Roommates").font(.subheadline.weight(.semibold))
                    Text("Sam passed 1h of doomscrolling today.").font(.subheadline)
                }
            }
            .card(Brand.surfaceContainerHigh, radius: 20, padding: 16)
        } bottom: {
            Button("Allow notifications") {
                Task {
                    _ = await Push.requestPermission()
                    await finish()
                }
            }
            .buttonStyle(BigButtonStyle())
            Button("Not now") { Task { await finish() } }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: Actions

    private var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    private var selectionSummary: String {
        var parts: [String] = []
        let c = selection.categoryTokens.count, a = selection.applicationTokens.count, w = selection.webDomainTokens.count
        if c > 0 { parts.append(c == 1 ? "1 category" : "\(c) categories") }
        if a > 0 { parts.append(a == 1 ? "1 app" : "\(a) apps") }
        if w > 0 { parts.append(w == 1 ? "1 website" : "\(w) websites") }
        return parts.joined(separator: ", ") + " picked"
    }

    private func agree() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await Account.signIn(displayName: name.trimmingCharacters(in: .whitespaces).ifEmpty("Anonymous"))
                Tracking.shared.refreshStatus()
                step = Tracking.shared.authorized ? .apps : .screenTime
            } catch {
                self.error = "Couldn't sign in. Check your connection and try again."
            }
        }
    }

    private func authorize() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await Tracking.shared.requestAuthorization()
                step = .apps
            } catch {
                self.error = "Screen Time access wasn't allowed. Doomscroll can't measure anything without it."
            }
        }
    }

    private func finish() async {
        step = .finishing
        try? Tracking.shared.start()
        await Tracking.shared.upload()
        await Push.sync()
        _ = try? await Groups.mine()
        router.finishOnboarding()
    }
}
