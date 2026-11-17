# Lumina R7 corrective candidate — prepared source only

This is a successor to the exact R6 source preserved in commit `174f68316d776ef437623e82f019e847e7b073e5`. R6 completed native verification with **72/79 cases passing** (59/61 unit and 13/18 UI); its unsigned Release archive and artifact verifier passed. R6 is retained with those failures. No R7 native result is claimed here.

## What changed

Exactly eight of the 119 candidate Source files change; the remaining 111 are byte-identical to R6. No source files are added or deleted. The seven existing bilingual support/privacy website files and all observed published branch histories remain preserved.

- Export items supply an app-owned, nonempty Transferable suggested filename for normal and raw recovery exports; the dialog derives its default from the same item. Real picker cancellation tests are retained unchanged.
- Offline-coach provenance and its explanation remain visible as separate text, with stable accessibility identities. The R6 language test stopped before relaunch when it could not find the standalone source text, so that result is not evidence of failed persistence.
- The existing privacy route moves to a compact first Settings section; English and Arabic largest-text reachability assertions are strengthened.
- The saved effort field gains an explicit accessible label and its persistence regression uses the stable existing identifier. R6 stopped before inspecting the saved value; no data-loss conclusion was drawn from that selector failure.
- Recovery validates bounded photo container framing before the existing bounded ImageIO decode. PNG chunk CRCs/tails, JPEG marker and outer EOI framing, GIF sub-blocks/trailer, and HEIF-family top-level box spans supplement the prior size/frame/pixel limits. Original bytes remain intact.
- The WAL fixture requests counters for the explicit `main` database and reads its pager first. The existing assertion proving committed WAL frames remain outside the main database is unchanged.

## Preservation and independent review

All **61 unit and 18 UI cases** remain selected. All 273 R6 UI assertion calls are retained verbatim with multiplicity (299 now). Every old unit `#expect` and `#require`, including trailing throwing closures, remains. Recovery assertions grow from 131 to 144 and required bindings from 25 to 27. Both UI methods that caused native export crashes remain byte-identical.

The existing runner's pure source-inventory and scheme/test-plan validators passed against the prepared source. The native runner, artifact verifier, test plan, project, privacy manifest, localization resources, and all other source files are unchanged. This check does not invoke Swift, Xcode, a simulator, scheduling, signing or store operations.

The six-file UI/export slice received an independent source review from `/root/career_readiness`. The two-file recovery slice was authored separately by `/root` and independently reviewed by `/root/lumina_review`; both reviews found no blocking source defect. Review qualifications and exact hashes are in the adjacent receipts.

## Native handoff and remaining limits

`candidate-source-manifest-v7-r7.json` seals the local 119-file staging Source plus the unchanged runner/tool. Its paths describe that staging location; root must independently seal actual Mac paths before native execution. The prior R6 manifest also declared a separate advertising-preparation root, which was not transferred into this source package. No advertising SDK, paid service or privacy declaration for an unintegrated SDK is added here.

Root exclusively coordinates the Mac and the next full 79-case native run plus unsigned archive. R7 has not yet proved the export crash resolved, largest-text layout, Arabic persistence, real-device file handling, VoiceOver, signing, upload, Apple review or public release.

Photo framing and bounded thumbnail decoding are not a proof of every encoded pixel or nested HEIF item extent. A size-zero BMFF box legitimately extends to EOF; other historical ImageIO formats retain the pre-existing decode gate. Valid-image and deliberately truncated-image regressions must run on the target SDK before acceptance.
