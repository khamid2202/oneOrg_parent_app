# OneOrg Parents (Flutter)

The parents' mobile app. Parents follow their children's school day: today's
lessons and changes, attendance, daily grades, points and class ranking, exams,
the school calendar and notifications. Same screens, API and wording (uz / ru /
en) as the web app in `SchoolProject/oneorg-parents`.

## Run

```bash
flutter pub get
flutter run                              # against https://api.oneorg.uz (prod)
flutter run --dart-define=MOCK=true      # built-in sample data, any login works
flutter run --dart-define=API_BASE_URL=https://dev-api.oneorg.uz
```

## Logging in

Phone number + SMS code only; no passwords and no DIS code.

1. The parent enters the phone number the school has on file for them as a
   guardian (`guardians.phone`).
2. The server texts a 5-digit code (valid 5 minutes, resend after 60 s), sent
   through Eskiz; see `/parent/auth/sms/request` and `/parent/auth/login/sms`.
3. The code logs in to every child linked to that phone. The token lasts 30
   days; after that, or after logging out, the parent gets a new code.

### Passkeys

After an SMS login the app offers to add a passkey (once per device; also under
Settings → Passkeys). Next time the parent taps "Log in with a passkey" and uses
Face ID, a fingerprint or the phone's passcode instead of an SMS. Backend:
`/parent/auth/passkey/options`, `/parent/auth/login/passkey` and
`/parent/auth/passkeys` (see oneorg-backend `docs/parent/auth.md`).

It works on a phone only when all of these are in place (the domain below is
`oneorg.uz`; change it everywhere if the server uses another):

1. **Server env:** `PARENT_WEBAUTHN_RP_ID=oneorg.uz` and
   `PARENT_WEBAUTHN_ORIGINS` listing `https://oneorg.uz` plus the Android app
   origins (the base64url SHA-256 of each signing certificate):
   - `android:apk-key-hash:tIZGkTXY9CZoTbDCqSk5E8kjK9dN4XHRJATsoVMuii4` (release key)
   - `android:apk-key-hash:ANfMBVxRLMh2oaSmyNgG4Rg8NGz0ECwvdsL5c0hZR5I` (debug key)
   - with Google Play App Signing, also the hash of Play's app signing key.
2. **Website:** serve `docs/well-known/apple-app-site-association` and
   `docs/well-known/assetlinks.json` at `https://oneorg.uz/.well-known/` as
   `application/json`, with no redirect (today the web app answers those paths
   with its HTML page).
3. **iOS:** in Xcode add the *Associated Domains* capability with
   `webcredentials:oneorg.uz` (already in `ios/Runner/Runner.entitlements`).
   Passkeys need iOS 16 or newer.


## Layout

```
lib/
  api/       api_client.dart (dio, bearer token, 401 → login), parent_api.dart
             (every /parent/* call), storage.dart, mock.dart (MOCK=true data)
  l10n/      strings.dart (uz/ru/en, from the web app's locale files), l10n.dart
  state/     auth, children (list + selected child), settings, query_cache
  screens/   auth_screens, shell (tabs, child switcher, bell), home, schedule,
             grades, attendance, more_screens (points, exams, calendar,
             notifications, settings)
  widgets/   theme, shared building blocks, Query (cached loading)
```

## Release build (Google Play)

```bash
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

- Application id: `uz.oneorg.parents`. Version comes from `version:` in
  `pubspec.yaml` (`1.0.0+1` = name 1.0.0, code 1); raise the `+N` for every
  upload, and keep `kAppVersion` in `lib/screens/more_screens.dart` in step.
- Signing: `android/key.properties` points at `android/upload-keystore.jks`.
  **Both are git-ignored; back them up somewhere safe** (password manager or
  team vault). Losing them means asking Google for an upload-key reset. Without
  `key.properties` the build falls back to debug keys, which Play rejects.
- Use Play App Signing (the default for new apps): this keystore is the upload
  key; Google holds the app signing key.

The default API is production (`https://api.oneorg.uz`), so a plain
`flutter build appbundle --release` is the store build.

## Backend notes

On the dev API today, grades, attendance and notifications return errors (no
branch context, a wrong column, a DTO that rejects `person_id`). The fixes are
in `oneorg-backend` but not deployed yet; the app shows a retry state for those
screens until then. See `SchoolProject/parents-backend-spec.md`.
