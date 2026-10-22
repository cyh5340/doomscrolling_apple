# App Store Connect answers (draft)

Re-check Apple's current guidelines before submitting. Screen Time apps get extra review.

## App Privacy ("nutrition label")

| Data type | Collected | Linked to the user | Used for tracking | Purpose |
|---|---|---|---|---|
| Usage Data → Product Interaction (time in picked apps, in 15-minute steps) | Yes | Yes | No | App Functionality |
| Contact Info → Name (display name, any text) | Yes | Yes | No | App Functionality |
| Identifiers → Device ID (FCM push token) | Yes | Yes | No | App Functionality |

Not collected: which apps are used, exact usage, location, contacts, advertising ID. The FamilyActivityPicker gives
the app opaque tokens, not app names, and exact minutes are only drawn by the sandboxed report extension, which
can't send data anywhere.

## Review notes

- **Family Controls:** the app uses `AuthorizationCenter.requestAuthorization(for: .individual)` for the user's own
  device. It only monitors (`DeviceActivity`). It never blocks apps or uses ManagedSettings shields.
- **Disclosure:** the first onboarding screen explains what's tracked, what friends see and what stays on the
  phone, with an explicit "I agree" before Screen Time access is requested.
- **Account deletion** (guideline 5.1.1(v)): Home → ⋯ → Delete account. It calls `delete_account()`, which deletes
  the user from `auth.users`; every table cascades from it. It also clears the device and stops monitoring.
- **Demo:** reviewers need two accounts in one group to see alerts. Give them an invite code to a seeded group.
- **Weekly stake:** see `TODO.md` §6 before submitting with stakes on.

## Privacy policy changes for iOS

The draft in the Android repo (`docs/privacy-policy.md`) describes Android. For iOS, add:

- Usage comes from Apple's Screen Time with your permission. You choose the apps; Doomscroll receives only a signal
  each time your total passes another 15 minutes, never the app names or exact time.
- Push notifications on iPhone also go through Apple Push Notification service (as well as Firebase Cloud
  Messaging).
- Turning off Screen Time access for Doomscroll in Settings stops tracking immediately.
