> **Current implementation: free on-device and local coaching.** The paid xAI client and API-key setup flow have been retired in every build configuration. No separate AI account or manual model download is required. See [FREE_LOCAL_RELEASE.md](FREE_LOCAL_RELEASE.md) for availability, fallback, privacy and verification boundaries.
>
> The older setup and offline-release notes below are retained as historical records; their cloud-model requirements and earlier AI capability descriptions do not apply to the current implementation. Signing and App Store credentials remain separate and unchanged.

---

# First offline iOS release

The owner selected the existing offline fitness/coaching version on 3 November 2026.

- Production (`Release`) builds ignore cloud API credentials and use the existing local coaching responses.
- All environment-key checks use `GrokService.configuredAPIKey`, which is absent in Release.
- Developer-only cloud plan/reflection controls are excluded from Release; chat identifies offline coaching.
- Debug builds retain the prior optional xAI integration. No provider API contract or authentication scheme changed.
- Existing fitness records, local features and storage are preserved. App Groups, push and iCloud capabilities were not removed to bypass provisioning.
- The Release-only `LuminaTests` regression supplies a dummy cloud key and checks that the reflection succeeds locally.

App Store privacy metadata must describe the final Release archive. Device/iCloud storage, permissions and deletion controls still require their own review; this change only disables production cloud-AI requests.

## Runtime and data controls — 15 November 2026

Fresh launch creates no sample profile, meals, workouts, check-ins or health measurements. Existing records remain preserved with a legacy-sample warning. Home, widget and Live Activity surfaces use recorded facts or neutral prompts; check-in streaks use consecutive dates and habit undo notes are factual.

The local SwiftData configuration explicitly disables managed CloudKit sync while preserving the previous default store location and App Group resolution. Existing capabilities remain configured. Startup failure displays a recovery message without resetting records.

Settings exports a standalone SQLite snapshot through the native file picker and requires confirmation before local deletion. Logging forms retain input and display save errors. Export, read-only rejection, deletion across all 14 model types and backup independence have fixture regression coverage. The privacy manifest declares the actual preferences API purposes; final App Store privacy metadata remains to be verified.

## Safe UI test configuration

UI automation requires the explicit `UI_TESTING` Swift compilation condition, `--lumina-ui-qa` launch argument and a UUID in `LUMINA_QA_ID`. It opens a separate temporary database and preferences suite, skips global reminder/widget updates and asserts an isolated-store marker before changing fixture records. A normal Release build excludes this path. Do not pass `UI_TESTING` to the production archive.

Automated tests do not establish manual VoiceOver or real-device permission acceptance. Health access is currently unavailable through Settings because the necessary purpose description is absent; this is shown clearly instead of requesting a permission. Distribution signing, hosted support/privacy pages and App Store Connect verification remain incomplete. No push, upload or submission is authorized by these local checks.
