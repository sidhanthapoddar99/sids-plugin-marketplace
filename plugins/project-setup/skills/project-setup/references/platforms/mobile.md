# Mobile — native iOS (Swift) + Android (Kotlin)

For projects that have a mobile surface. The Notes call out **native** apps in this stack — not React Native, not Flutter.

## When this fits

- Real mobile app, not just a responsive web view
- Native UX matters (gestures, platform-specific affordances, performance)
- Two separate codebases is acceptable (small teams often pick this anyway because the alternative cross-platform pain often equals it)

When cross-platform is justified (small team, simple UI, lots of shared business logic), Flutter or React Native are valid — but **not** the default here.

## Layout (under a monorepo)

```
my-app/
├── apps/
│   ├── backend/                    # shared API
│   ├── frontend/                   # web — optional
│   ├── mobile-ios/
│   │   ├── README.md
│   │   ├── MyApp.xcodeproj/         # or Package.swift if SPM
│   │   ├── MyApp/                   # Swift sources
│   │   │   ├── App.swift
│   │   │   ├── Views/
│   │   │   ├── Models/
│   │   │   ├── Services/            # API clients
│   │   │   └── Resources/
│   │   ├── MyAppTests/
│   │   └── fastlane/                # if using fastlane for builds/release
│   └── mobile-android/
│       ├── README.md
│       ├── build.gradle.kts
│       ├── settings.gradle.kts
│       ├── app/
│       │   ├── build.gradle.kts
│       │   └── src/
│       │       ├── main/
│       │       │   ├── java/com/example/myapp/   # or kotlin/
│       │       │   ├── res/
│       │       │   └── AndroidManifest.xml
│       │       ├── test/
│       │       └── androidTest/
│       └── gradle/
└── …
```

`mobile-ios/` and `mobile-android/` live under `apps/` like other apps. Each has its own toolchain — Xcode for iOS, Gradle/Android Studio for Android.

## Per-platform contract

Both apps:

- Hit the same backend via `/api/*` (HTTPS in prod, plain HTTP via dev-machine IP in dev)
- Use the same OpenAPI/proto schema → generated clients (or hand-written, but ideally generated)
- Share a `.env`-equivalent for build-time config (`Config.xcconfig` for iOS, `gradle.properties` for Android)

Don't try to share code between iOS and Android. The native UI worlds are too different. Share at the **API contract** level instead.

## `ctl` integration

`ctl` doesn't run the mobile apps — those are IDE-driven (Xcode / Android Studio). But `ctl` can:

```bash
ctl mobile-ios          # opens MyApp.xcodeproj in Xcode (macOS only)
ctl mobile-android      # opens apps/mobile-android in Android Studio
ctl mobile-api-codegen  # regenerate clients from the backend's OpenAPI
```

## CI/CD

- **iOS**: Xcode Cloud, GitHub Actions with macOS runner, or Bitrise. fastlane for the release pipeline.
- **Android**: GitHub Actions with `ubuntu-latest` + Java + Android SDK setup actions. Gradle wrapper handles the rest.

CI is the only realistic place to build releases — local builds for daily dev, CI for tagged releases.

## Versioning

Independent per-platform version (semver). Both reference the same backend API version — backend changes require coordinated rollout.

## Anti-patterns

- One bundled "mobile" folder with iOS and Android intermixed — keep separate
- Forcing cross-platform when team and product warrant native — re-evaluate annually
- Letting mobile lag the backend's API schema — break PRs early in CI by running mobile codegen
- Per-developer signing certs without 1Password-style secrets — onboarding suffers
- API base URL hard-coded — use build flavours (debug vs release) with different bases

## See also

- `references/env-and-config/build-time-vs-runtime.md` — mobile is heavily build-time
- `references/ci-cd-future.md` — adapt for mobile-specific runners
- `references/examples-index.md` — Sid doesn't have a published mobile example yet
