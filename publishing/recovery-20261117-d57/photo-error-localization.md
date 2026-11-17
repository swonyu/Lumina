# Photo error language correction after frozen R11

Status: source prepared; native compilation and execution of this delta are pending.

Parent: `74fef9d156edd897e3553112ea7ff63b03611320`. The original R11 native
package and its Mac run remain frozen at that parent. Their results cannot
establish acceptance of this later change.

## Validated finding

`LocalPhotoImport` localized a load-failure or cancellation message when storing
it. Both photo views subsequently localized the stored string again when
rendering it. An error produced in Arabic therefore became an Arabic catalog
lookup key. The English catalog contains the original English keys, not their
Arabic translations, so changing the app to English retained an Arabic error.

The path is: select Arabic; encounter a failed photo import or navigate away
while an import is pending; select English in Settings; return to the preserved
meal or progress-photo state. Existing data and cancellation guards are not the
cause. This was established by source and actual catalog inspection, not by a
new native UI execution.

The two assignments now retain the original localization keys. Existing views
already call `L(error)` during rendering, so they select the current translation.
No import, validation, cancellation, save, image-byte or draft-retention behavior
changes. Both translations already exist; no catalog changes are needed.

## Focused regression and native implications

Added `PhotoImportIntegrityTests/retainedPhotoErrorsRelocalizeInBothDirections()`.
It exercises a real failing loader and a canceled controlled loader, checks
that neither publishes bytes or invokes its save callback, then renders both
retained keys through the real English and Arabic catalogs in both directions.
It uses its own preference suite and does not change shared language state.
All five prior photo-import tests and all other unit/UI test source are retained.

The unit inventory increases from 61 to **62** methods. UI remains **21** methods.
The final candidate runner must add the exact new unit selector to its expected
leaf inventory and bind the new source manifest; do not weaken result checks or
change the frozen parent runner. Run the affected photo suite with Arabic app/test
language as well as the complete final suite. On the parent, Arabic initialization
makes the eager-localization error observable directly in the new key assertion;
an English-only run can mask the original asymmetry.

Linux source checks establish the two changed assignments, existing rendering
call sites, catalog coverage, original-test retention and clean diff formatting.
They are not Swift compilation or executed native test results.

## Bounded reliability review

The associated read-only review traced backup staging, fixed-schema untrusted
SQLite validation, immutable export projection, transactional empty-journal
restore, data-deletion session guards, photo import replacement/cancellation,
model availability, bounded coaching context, refusal handling, deadlines and
late-response admission. It found no additional validated defect in those paths.

Existing native test source covers all fourteen restored model kinds, relationship
and exact-date preservation, independent persistent reopen, rollback before
restore commit, rejected nonempty/dirty/read-only destinations, malformed inputs,
owned staging cleanup, canceled loader races and the earlier Habit schema's
persisted migration. Those cases remain required native evidence; this review
does not relabel historical results or establish new passes.

Language and reminder preferences remain outside recovery import. Recovery UI
already stores message keys correctly. All 48 directly identified recovery/photo
UI message keys in the reviewed paths exist in both language catalogs. Actual
system-model answer quality remains a separate supported-device gate.
