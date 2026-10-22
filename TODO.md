# TODO: needs you (accounts, domains, devices)

The app builds and runs against the local Supabase stack. These steps need your accounts or a real iPhone.
Unlike the Android side, an **Apple Developer Program membership** ($99/year) is needed to run Screen Time on a
device beyond a free provisioning profile's limits, and to ship.

## 1. Signing and Screen Time entitlement

- Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM`.
  Xcode's automatic signing then registers the App Group (`group.com.doomscroll.app`), push, and Family Controls
  (development) for the app and both extensions.
- If `com.doomscroll.*` is taken in your team, change `BUNDLE_ID_PREFIX` and `APP_GROUP` there too.
- **Before TestFlight or the App Store:** request the *Family Controls (Distribution)* entitlement with Apple's
  request form (developer.apple.com, under Contact → Request) for **all three** bundle IDs:
  `com.doomscroll.app`, `.app.monitor` and `.app.report`. Approval can take a while; request it early.
  Development builds work without it.

## 2. Supabase (shared with Android)

Use the project from the Android repo's `TODO.md`. In `Config/Local.xcconfig`:

```
SUPABASE_URL = https:/$()/<ref>.supabase.co
SUPABASE_KEY = <publishable key>
```

(`/$()/` is needed because xcconfig treats `//` as a comment.) No backend changes are needed for iOS.

## 3. Push (Firebase, same project as Android)

```sh
npx firebase-tools apps:create IOS "Doomscroll" --bundle-id com.doomscroll.app --project doomscroll-<suffix>
npx firebase-tools apps:sdkconfig IOS <appId> --project doomscroll-<suffix> -o App/GoogleService-Info.plist
xcodegen   # picks up the new plist
```

- Create an APNs auth key: developer.apple.com → Keys → "+" → Apple Push Notifications service. Upload the `.p8` in
  Firebase console → Project settings → Cloud Messaging → Apple app configuration.
- `GoogleService-Info.plist` is git-ignored. Until it exists, push is off and everything else works.
- Optional, in the Android repo's `send-alert/index.ts`: iOS notifications are silent unless the message asks for a
  sound. Add `apns: { payload: { aps: { sound: "default" } } }` next to `android: { priority: "high" }`.
- Firebase is pinned to 12.x on purpose: 13.x deprecates FCM registration tokens in favor of installation IDs,
  which `send-alert` doesn't send to.

## 4. Invite links (same domain as Android)

- Set `INVITE_HOST` in `Config/Local.xcconfig`.
- Put `web/.well-known/apple-app-site-association` next to `assetlinks.json` on that host (in the Android repo's
  `backend/web/`). Replace `REPLACE_WITH_TEAM_ID`, serve it as `application/json` with no redirects.
- Add an App Store link to `backend/web/join/index.html` once the app is listed.
- Until then, invites work by pasting the link or code into "Create or join".

## 5. Sign in with Apple (later)

Accounts are anonymous for now, so deleting the app loses the account. To keep it, enable the Apple provider in
Supabase Auth and link it to the anonymous user (`supabase.auth.linkIdentityWithIdToken`) so existing data is kept.

## 6. Weekly stake payments

Same ledger as Android (see the Android repo's `TODO.md`). For the App Store as well: real money isn't a digital
good, so it doesn't go through in-app purchase, but App Store Review Guideline 5.3 covers contests and real-money
gaming. Get legal advice, and check the guideline as it stands when you submit.

## 7. Device testing

- Screen Time doesn't work in the simulator. On an iPhone, compare Debug → "Friends see today" with
  Settings → Screen Time over a normal day (Debug rounds down to 15 minutes; Screen Time shows exact time).
- Check that the monitor extension uploads with the app closed: pass a bucket with the app swiped away, then look
  for the row in Supabase (`events`, `platform = 'ios'`), or open Debug → "Last extension callback".
- An iPhone and an Android phone in one group: either passing the daily limit notifies the other.
- Watch for early threshold callbacks right after monitoring starts (seen on some iOS 17 builds). The extension
  ignores a bucket that couldn't have been reached yet (45 minutes before 00:45), but check Debug's outbox.
