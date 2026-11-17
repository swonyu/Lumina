> **Current implementation: free on-device and local coaching.** The paid xAI client and API-key setup flow have been retired in every build configuration. No separate AI account or manual model download is required. See [FREE_LOCAL_RELEASE.md](FREE_LOCAL_RELEASE.md) for availability, fallback, privacy and verification boundaries.
>
> Older setup and offline-release documents elsewhere in this repository are retained as historical records; their cloud-model requirements and earlier AI capability descriptions do not apply to the current implementation. Signing and App Store credentials remain separate and unchanged.

---

# Lumina

An iOS personal-coaching and wellness journal built with SwiftUI and SwiftData.

This checkout prepares the owner-selected offline release. It is not yet approved or publicly released in the App Store.

## Current behavior

- Every build configuration uses the same free on-device coaching route: the system model when available for the device and language, otherwise clearly identified local general suggestions. The app does not make paid-provider requests or require an API key.
- Fresh installs start without sample profiles, activity or health measurements. Earlier prototype records are preserved; review them before treating them as personal measurements.
- Home shows saved journal counts and consecutive check-in days. Unvalidated health scores and causal habit/photo claims are not presented as measured results.
- Workouts, meals, check-ins, habits, goals, journal entries and progress photos remain local features.
- Settings offers a SQLite backup, preview of supported backups, and confirmed restoration into an empty local journal. Raw recovery copies and older database exports cannot be restored by this version. Deletion requires explicit confirmation and leaves exported copies and Apple Health data intact.

## Development and verification

Open `Lumina.xcodeproj`, scheme `Lumina AI personal trainer`, with a compatible SDK (deployment target iOS 26.5; Swift 5 language mode).

Debug, UIQA and Release do not read `XAI_API_KEY` or send coaching context to xAI. The legacy `GrokService` and `SmartGrokCoach` entry points ignore their optional key argument and use local rules. The current chat uses `OnDeviceCoach`; see [FREE_LOCAL_RELEASE.md](FREE_LOCAL_RELEASE.md) for its system-model availability and fallback behavior.

Release tests cover sample-free launch, preservation, consecutive-day streaks, backup round-tripping, isolated deletion, read-only save rejection and local coaching. `ci_scripts/verify_release_archive.py` checks archive icons, their metadata and the selected Release iCloud environment; actual distribution signing must be verified separately.

Privacy permission configuration, manual screen/accessibility/device QA, provisioning, support/privacy URLs and App Store metadata remain release gates. A push may trigger Xcode Cloud; check workflow actions and authorization before pushing.

The recovered R11 meal-readability changes and additional UI assertions are committed source, pending native verification. The earlier R9 result was 78/82 (61 unit and 17 UI passes), with four UI failures; it is not an R10 or R11 acceptance result. See [the recovery record](publishing/recovery-20261117-d57/STATUS.md) for exact source identity and remaining gates.
