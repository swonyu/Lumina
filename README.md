> **Current implementation: free on-device and local coaching.** The paid xAI client and API-key setup flow have been retired in every build configuration. No separate AI account or manual model download is required. See [FREE_LOCAL_RELEASE.md](FREE_LOCAL_RELEASE.md) for availability, fallback, privacy and verification boundaries.
>
> The older setup and offline-release notes below are retained as historical records; their cloud-model requirements and earlier AI capability descriptions do not apply to the current implementation. Signing and App Store credentials remain separate and unchanged.

---

# Lumina

An iOS personal-coaching and wellness journal built with SwiftUI and SwiftData.

This checkout prepares the owner-selected offline release. It is not yet approved or publicly released in the App Store.

## Current behavior

- Release builds disable external cloud-coaching credentials and use local general suggestions.
- Fresh installs start without sample profiles, activity or health measurements. Earlier prototype records are preserved; review them before treating them as personal measurements.
- Home shows saved journal counts and consecutive check-in days. Unvalidated health scores and causal habit/photo claims are not presented as measured results.
- Workouts, meals, check-ins, habits, goals, journal entries and progress photos remain local features.
- Settings offers a SQLite backup and explicit confirmation before deleting local records. Exported copies and Apple Health data are not deleted. In-app backup restore is not implemented.

## Development and verification

Open `Lumina.xcodeproj`, scheme `Lumina AI personal trainer`, with a compatible SDK (deployment target iOS 26.5; Swift 5 language mode).

Debug may optionally use a developer `XAI_API_KEY` and send coaching context to xAI. Release ignores that key. Do not treat build-time secrets as runtime production credentials.

Release tests cover sample-free launch, preservation, consecutive-day streaks, backup round-tripping, isolated deletion, read-only save rejection and local coaching. `ci_scripts/verify_release_archive.py` checks archive icons, their metadata and the selected Release iCloud environment; actual distribution signing must be verified separately.

Privacy permission configuration, manual screen/accessibility/device QA, provisioning, support/privacy URLs and App Store metadata remain release gates. A push may trigger Xcode Cloud; check workflow actions and authorization before pushing.
