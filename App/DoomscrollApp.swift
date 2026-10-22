import BackgroundTasks
import DoomscrollKit
import Observation
import SwiftUI
@preconcurrency import UserNotifications

enum Route: Hashable {
    case group(String)
    case newGroup
    case join(String)
    case debug
}

/// Navigation, plus screens to open from a notification tap or an invite link.
@MainActor @Observable
final class Router {
    static let shared = Router()
    var path: [Route] = []
    var onboarded = SharedSettings.shared.onboarded

    func open(_ route: Route) {
        if onboarded { path = [route] }
        else if case .join(let code) = route { SharedSettings.shared.pendingInvite = code } // opened after onboarding
    }

    func finishOnboarding() {
        SharedSettings.shared.onboarded = true
        onboarded = true
        if let code = SharedSettings.shared.pendingInvite {
            SharedSettings.shared.pendingInvite = nil
            path = [.join(code)]
        }
    }

    func reset() {
        path = []
        onboarded = false
    }
}

@main
struct DoomscrollApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let router = Router.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .tint(Brand.primary)
                // Invite links: https://<inviteHost>/join/{code}. Needs apple-app-site-association on that host.
                .onOpenURL { url in
                    if let code = inviteCode(from: url) { router.open(.join(code)) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { AppDelegate.scheduleUpload() }
        }
    }
}

struct RootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        if router.onboarded {
            NavigationStack(path: $router.path) {
                HomeView()
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .group(let id): GroupView(groupId: id)
                        case .newGroup: NewGroupView()
                        case .join(let code): JoinView(code: code)
                        case .debug: DebugView()
                        }
                    }
            }
        } else {
            OnboardingView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let uploadTask = "com.doomscroll.app.upload"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Push.configure()
        application.registerForRemoteNotifications()
        // Backup for uploads the monitor extension couldn't finish (offline at the time).
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.uploadTask, using: nil) { task in
            Self.scheduleUpload()
            let work = Task { @MainActor in
                let ok = await Tracking.shared.upload()
                task.setTaskCompleted(success: ok)
            }
            task.expirationHandler = { work.cancel() }
        }
        return true
    }

    static func scheduleUpload() {
        guard OutboxStore.shared.oldestPending() != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: uploadTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Push.didRegister(apnsToken: deviceToken)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Tapping a friend alert opens that group.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let groupId = response.notification.request.content.userInfo["groupId"] as? String {
            await Router.shared.open(.group(groupId))
        }
    }
}
