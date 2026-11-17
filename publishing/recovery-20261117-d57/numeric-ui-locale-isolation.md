# Arabic numeric formatting without changing native-control locale

## Observed R13 failure

Frozen source `add412734658eef9aece0ec19618841f00ecc2c9` ran in
`20261117T151948Z-6086-5a1c44498e`. The retained
`testArabicDecimalDraftPersistsAcrossAppLanguagesOnEnglishDevice` journey saved
its real Arabic-decimal workout, relaunched in Arabic, and opened the saved
workout editor. The app then terminated with `EXC_CRASH / SIGABRT` on the main
thread. The test failed after 134.907 seconds, before reaching its final
`12٫5` equality assertion.

The original crash report is
`/Users/saleh/Library/Logs/DiagnosticReports/Lumina-2026-11-17-182655.ips`,
71,352 bytes, SHA-256
`21b99e05a291fb88ede5b1c2e0f0349c38991aa01635639eb86143c814e19986`.
Its exception backtrace enters `NSArray.initWithObjects`,
`_UIDatePickerIOSCompactView._updateUI`, `didChangeLocale`,
`UIDatePicker.setLocale`, and SwiftUI's date-picker representable update.
The screened frame summary is in `r13-native/crash-summary.json`; the full
original report is preserved separately for native diagnosis.

R12 changed the global Arabic locale from `ar` to `ar-u-nu-arab` to repair the
reopened decimal separator. That also supplied the numeric override to native
date controls. R11 had reached the same editor and failed only the decimal
comparison; the new R13 crash occurs inside locale application to its compact
date picker. This identifies the numeric/UI locale boundary as the repair
target. A native rerun must still establish that the repair works.

## Product change

`AppLanguage.locale` again supplies ordinary `en` or `ar` to the SwiftUI
environment, date formatters, date pickers and coaching language selection.
The new `numericLocale` selects an Arabic numeric format only
for `LocalRecordDraft.numberText` and `LocalRecordDraft.number`. Those helpers
continue to format `12.5` as `12٫5` for Arabic, accept both supported decimal
marks and Arabic digits after a live language switch, and preserve the stored
number's round-trip precision. No record, draft, picker or editor was removed.

The same R13 run also recorded three unit issues in two methods: the
`ar-u-nu-arab` identifier reported numbering system `yes`, a nil decimal
separator, and formatted `12.5` as `12.5`. Simply moving that malformed locale
out of the UI environment would not fix numeric formatting. The numeric
policy therefore uses `ar_SA`, whose `0٫25` formatting assertion passed in
that very native run. The helpers read only its decimal separator; no region
or calendar is added to the UI locale. The numbering-system, separator and
`12٫5` assertions all remain required for the next native run.

## Regression coverage and evidence limits

All 62 unit method names and all 21 selected UI journeys are retained. The
Arabic-decimal test body, including its final `12٫5` assertion, is unchanged.
Separate evidence-backed interaction repairs address three other UI failures;
they are documented in `r13-native/ui-failures-and-repairs.json`. All four
production saved-record `DatePicker` declarations and the entire editor file
are unchanged.

The three numeric-locale expectations added in R12 now target `numericLocale`.
Their expected numbering system and decimal marks are unchanged. New checks
require the UI locale identifiers to remain ordinary `en` and `ar`, and saved
record formatting checks use the same numeric policy as the production
helpers. Retaining R12's incorrect assumption that the *global UI locale*
must carry the numeric override would reintroduce this crash.

An independent read-only source review by `/root/github_recovery` found no
blocking issue in the locale change or its use sites. File checks show
unchanged method inventory, retained UI outcome assertions and unchanged date-picker
source. Swift/native compilation and the repaired journey have not been run
by this child agent. The original R13 run remains independent evidence and
was not edited or stopped.

The next acceptance check is the original Arabic-decimal journey on the real
simulator. A focused pass is only a focused pass; the complete 83-case suite
and production archive gates remain necessary for the final candidate.

## Primary API references

- Apple documents that a date picker's locale affects its display language
  and date/time format: https://developer.apple.com/documentation/uikit/uidatepicker
- Apple documents the numbering-system override separately:
  https://developer.apple.com/documentation/foundation/locale/components/numberingsystem

These references describe API boundaries. The reported crash is established
by the actual R13 crash record, not inferred from the documentation.
