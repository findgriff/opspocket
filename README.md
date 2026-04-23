# OpsPocket — iPhone app

Flutter/iOS client for SSH, OpenClaw, and VPS ops — from your phone.

**Bundle ID:** `co.opspocket.opspocket`
**Platform:** iOS 13+
**Flutter:** 3.41.7 / Dart 3.11.5
**Team:** RT2UR47KNW

## What's in this repo

```
lib/              — all Dart feature code (Riverpod + GoRouter)
ios/              — native iOS shell (Info.plist, Runner.xcworkspace)
android/          — (present but not actively built)
test/             — Dart unit + widget tests
assets/           — logos + fonts
pubspec.yaml      — dependency lock
```

## What's NOT in this repo

The **SaaS platform** (Cloud backend + marketing site + admin dashboard +
tenant installer + Caddy configs) lives at
**[findgriff/opspocket-platform](https://github.com/findgriff/opspocket-platform)**.

The app ↔ platform coupling is **HTTPS-only** — the app calls
`opspocket.com/api/pair/<code>` etc. Neither repo imports the other.

## Quick build

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test

# Release install on a paired iPhone
xattr -cr .
flutter build ios --release
DEV=<your-device-uuid>
xcrun devicectl device install app --device $DEV build/ios/iphoneos/Runner.app
```

Full operating context in `HANDOVER.md` + `CLAUDE.md`.

## License

See `LICENSE`.
