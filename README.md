# Doomscroll for iPhone

The iOS version of [doomscrolling_android](https://github.com/cyh5340/doomscrolling_android). It tracks time in
"doomscroll" apps, alerts a friend group when someone passes a limit, ranks friends on a leaderboard, and runs the
weekly stake. It uses **the same Supabase backend** (`backend/` in the Android repo) without changes, so iPhone and
Android friends can share one group.

SwiftUI, iOS 17.4+, no third-party UI code. What still needs your accounts or a real iPhone is in [TODO.md](TODO.md).

## How it maps to the Android app

| | Android | iPhone |
|---|---|---|
| Reading usage | UsageStatsManager events, sessions rebuilt on the device | Screen Time (`DeviceActivity`). iOS calls a monitor extension each time today's usage passes another 15 minutes. The app never sees exact minutes. |
| Which apps | Bundled list of package names | The user picks apps or categories in Apple's picker. Opaque tokens only. Everything picked is reported as `social`. |
| What's reported | `bucket_reached` every 15 min, plus `session_threshold` | `bucket_reached` only. iOS can't detect single sessions, as the Android plan already assumed. The rest of the group still gets session alerts from Android members. |
| Upload | WorkManager every 15 min | The monitor extension uploads as soon as a bucket is reached. The app retries on launch, when it returns to the foreground, and in a background refresh task. |
| Today screen | Exact minutes from the device | Exact minutes drawn by a `DeviceActivityReport` extension, sandboxed so the app itself can't read them |
| Push | FCM | FCM (Firebase Messaging over APNs), so `send-alert` is unchanged |
| Invite links | App Links + `assetlinks.json` | Universal Links + `web/.well-known/apple-app-site-association` |
| Account | Anonymous Supabase auth | Same |

Everything else matches the Android app: the prominent disclosure before any data is collected, groups with presets,
"most" vs "least wins" ranking, the live leaderboard (Supabase Realtime), the weekly stake pot and past weeks, stake
consent on the join screen, mute, leave, in-app account deletion, the debug screen and the brand colors.

## Layout

```
App/                    SwiftUI app: onboarding, home, groups, leaderboard, join, debug
  Backend.swift         Supabase client, models, groups/leaderboard/stake calls (mirrors core/network)
  Tracking.swift        Screen Time authorization, the picked apps, the daily monitoring schedule
  Push.swift            Firebase Messaging; a no-op until GoogleService-Info.plist exists
MonitorExtension/       DeviceActivityMonitor: records each 15-min bucket and uploads it
ReportExtension/        DeviceActivityReport: draws the Today ring with exact minutes
Packages/DoomscrollKit/ Code shared by all three targets: buckets, outbox, uploader, formatting, brand
Config/                 xcconfig: Supabase URL/key, invite host, team, App Group
web/.well-known/        apple-app-site-association for the invite domain
docs/app-store.md       App Privacy answers, review notes, privacy-policy changes for iOS
project.yml             XcodeGen spec (the generated Doomscroll.xcodeproj is committed)
```

### Data flow

```
iOS Screen Time ──(bucket.45 reached)──▶ MonitorExtension ──▶ outbox.json (App Group)
                                               │                        ▲
                                               ▼                        │ retry on launch /
                                    POST /rest/v1/events ◀──────────────┘ background refresh
                                               │
                     Supabase: on_event trigger → daily_usage, alerts → send-alert → FCM → friends
```

The monitor extension and the app share the signed-in session through the App Group's Keychain access group, so
the extension can upload without the app running. Events have client-generated UUIDs and are inserted with
`on conflict do nothing`, so resends are harmless. The outbox also skips a bucket already recorded that day, because
iOS repeats threshold callbacks when monitoring restarts.

## Run it

Built and tested with Xcode 26.2 (iOS 26.2 SDK).

```sh
# 1. Backend: in the Android repo
cd ../doomscrolling_android/backend && npx supabase start

# 2. App
open Doomscroll.xcodeproj        # run the Doomscroll scheme
```

The defaults point at the local stack on `127.0.0.1:54321`, which the simulator can reach. To use a real project,
copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`.

**Screen Time only works on a real iPhone.** In the simulator, onboarding, groups, the leaderboard and invites
work, but the Screen Time permission and the app picker don't, so nothing is measured.

After editing `project.yml`, regenerate the project with `brew install xcodegen && xcodegen`.

## Tests

```sh
cd Packages/DoomscrollKit && swift test
```

17 tests cover bucket naming and thresholds, outbox deduplication and pruning, the local date in the user's time
zone, the exact `events` request the uploader sends, invite-code parsing, and Monday week starts.
