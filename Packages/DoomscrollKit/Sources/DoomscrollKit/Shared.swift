import Foundation

/// Build settings, read from each target's Info.plist (filled from Config/*.xcconfig).
public enum AppConfig {
    private static func value(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Defaults target the local Supabase stack (`npx supabase start` in the Android repo's backend/),
    /// which the simulator reaches on 127.0.0.1.
    public static var supabaseURL: URL { URL(string: value("DSSupabaseURL") ?? "http://127.0.0.1:54321")! }
    public static var supabaseKey: String { value("DSSupabaseKey") ?? "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH" }
    public static var inviteHost: String { value("DSInviteHost") ?? "doomscroll.example" }
    /// App Group shared by the app and its extensions. Also the Keychain access group for the signed-in session.
    public static var appGroup: String { value("DSAppGroup") ?? "group.com.doomscroll.app" }
    /// Key the Supabase session is stored under, the same in the app and the monitor extension.
    public static let authStorageKey = "doomscroll.auth"
}

public enum SharedContainer {
    /// The App Group container, or the app's own Application Support where there is none (unsigned simulator builds).
    public static var url: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

/// Small settings the app and its extensions share.
public final class SharedSettings: @unchecked Sendable {
    public static let shared = SharedSettings()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = UserDefaults(suiteName: AppConfig.appGroup)) {
        self.defaults = defaults ?? .standard
    }

    /// The FamilyActivitySelection the user picked, encoded. Opaque tokens only; no app names.
    public var selection: Data? {
        get { defaults.data(forKey: "selection") }
        set { defaults.set(newValue, forKey: "selection") }
    }

    /// Strictest daily limit among the user's groups, for the Today ring in the report extension.
    public var dailyLimitMinutes: Int? {
        get { defaults.object(forKey: "dailyLimitMinutes") as? Int }
        set { defaults.set(newValue, forKey: "dailyLimitMinutes") }
    }

    /// Invite code from a link, kept until onboarding finishes and the join screen opens.
    public var pendingInvite: String? {
        get { defaults.string(forKey: "pendingInvite") }
        set { defaults.set(newValue, forKey: "pendingInvite") }
    }

    public var onboarded: Bool {
        get { defaults.bool(forKey: "onboarded") }
        set { defaults.set(newValue, forKey: "onboarded") }
    }

    /// Last time the monitor extension got a threshold callback (debug screen).
    public var lastCallbackAt: Date? {
        get { defaults.object(forKey: "lastCallbackAt") as? Date }
        set { defaults.set(newValue, forKey: "lastCallbackAt") }
    }

    /// Last upload error from the extension, if the most recent attempt failed (debug screen).
    public var lastUploadError: String? {
        get { defaults.string(forKey: "lastUploadError") }
        set { defaults.set(newValue, forKey: "lastUploadError") }
    }

    public func clear() {
        for key in ["selection", "dailyLimitMinutes", "pendingInvite", "onboarded", "lastCallbackAt", "lastUploadError"] {
            defaults.removeObject(forKey: key)
        }
    }
}
