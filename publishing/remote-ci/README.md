# Lumina R23 V9: bounded completion and failure evidence

**Proposed, root unbound, native unrun.** This distinct first-attempt hosted
workflow continues app commit `02c7cfc11cd8b6049e67cc0d767079363d8aa6ca` and tree
`31a9678032b666414d44d9691e64908f850f2108`. All 190 app files, all 120 staged native
files, all 69 unit identities and all 21 UI identities remain unchanged. No app
test assertion, device, SDK, filter, retry, signing or store gate is relaxed.
The branch is `continuation/publishing-r23-remote-ci-v9-d57`.

## Actual failure requiring this change

Run `44365142824`, attempt 1, control `8c545102bba575b23a216e537b7a43a2d7fbf5f8`
failed. The recovered 32 KiB stdout tail proves 21 UI tests executed with five
failure events, one unexpected, in 1,747.969 seconds. It does not identify five
distinct failed cases, establish 16 passes, or recover the 69-unit verdict.
The last visible UI case passed. SIGTERM arrived 38.665 seconds after the UI
suite finished, at the 2,300-second command ceiling. The result bundle lacked
its `Info.plist`, preventing a complete summary/tree read.

The failed-test path then started a production archive with only 87.999 seconds
remaining of its requested 900. It was interrupted; the normal final source
snapshot hit the work deadline and never completed. Cleanup reported owned
groups closed, the owned simulator shut down and the lock released. Those
checks do not identify or exclude separately sessioned build services. A newly
observed `AIChatView.o` cache file had an mtime 17.294 seconds after the final
report. Its writer is unknown. GitHub later reported an orphan `ibtoold`; no
causal link is asserted. The strict collector rejected the unindexed file and
uploaded no artifact.

The original complete 30,986-byte report, whole stderr, seven captures, 38
hash-matched command/status records and full decoded console are preserved in
the separate V6 diagnostic package. Full stdout, xcresult, screenshots and
archive were not recovered. Five UI failure events remain unresolved; this
control proposal does not repair or reinterpret them.

## Composed time limits and admission

The native envelope is exactly 75 minutes (4,500 seconds):

| Phase allocation | Seconds |
|---|---:|
| Setup before test admission | 390 |
| Full test command, including result finalization | 2,700 |
| Summary and tree inspection | 120 |
| Production settings | 90 |
| Production archive | 900 |
| Archive verifier | 120 |
| Normal final source checks | 60 |
| Owned cleanup and bounded final source recheck | 120 |
| Total | 4,500 |

The test command requires at least 3,990 seconds of remaining work time. The
archive requires at least 1,170 seconds for settings, archive, verifier and
final source checks. This prevents knowingly truncated release phases. The
test ceiling adds 400 seconds, yielding about 435 seconds after the measured
V6 UI-suite finish for finalization. This is an unverified engineering allowance,
not a prediction of test success. R19 used a different Mac/iOS 27 beta platform;
its shorter duration is historical context, not current acceptance.

The outer job is 90 minutes. Step ceilings compose as checkout 1 minute,
preparation 3, native invocation 76 (75-minute runner plus startup margin),
complete collection 4, conditional diagnostic preparation 2, one conditional
upload route 3, and final gate 1. The fallback route totals 90 minutes; the full
route omits the two diagnostic minutes. Preparation and native launch each
require the full 90-minute envelope remaining before the unchanged user
deadline, `2026-11-18T22:26:12Z`.

## Failed tests and final source verification

Production runs only after the full test command, summary, tree and exact
90-case acceptance all pass. A failed gate records
`skipped_after_failed_test_gate`, keeps the archive gate unsatisfied and
preserves test evidence. A full pass still requires the unchanged archive
contents and archive verifier.

After owned cleanup, a read-only source and frozen-manifest recheck is bounded
by the remaining native deadline and 20 seconds. It cannot repair source. It
records changed, unchanged or unverified source while preserving failed or
interrupted native status. Acceptance additionally requires this final check
and its actual `after-cleanup` manifest receipt to pass. Existing process-group,
simulator identity/shutdown and lock rules remain unchanged. No process-name
kill, forced lock removal or connected-Mac native permission is added.

## Complete evidence and separate diagnostics

The collector performs at most three complete inventories, with two 20-second
observation intervals, within a 60-second inventory bound. Every retained
original and every existing-policy omitted cache member participates. Exact
additions, removals and changes are recorded; two consecutive inventories must
agree. The original unindexed-late-file rejection remains intact, including late
cache files and symlinks. Full retained/omitted inventories are also compared
after packing and byte verification. No new exclusions or deletions exist.

If complete collection fails, a separately named **INCOMPLETE** diagnostic
artifact can preserve entire raw reports, command/results, stdout/stderr and
failure/inventory records. Both its selected originals and compressed ZIP are
capped at 20,000,000 bytes. Oversized, changing, replaced, linked or unbounded
originals fail closed without truncating the artifact. Descriptor/path identity,
whole-file SHA256, source membership, ZIP CRC and ZIP byte equality are checked.
No xcresult, screenshot or archive is included. This route cannot satisfy the
native or complete-evidence gate: its output keys and upload identity are
separate. The full and diagnostic upload routes are mutually exclusive through
the collector outcome.

Failed test stdout also receives a console fallback of at most 2 MiB with the
existing strict descriptor/path provenance. V6 stdout was 890,085 bytes, so this
bound would have retained it completely. Larger files remain explicitly partial
with exact offsets and capture hashes; they receive no whole-file hash. Console
diagnostics cannot make a native failure pass.

## Authority, costs and remaining gates

Only a root-bound, public, standard `macos-26` GitHub VM can execute the first
attempt with Xcode 26.6 build 17F113 and iOS 26.5 on an owned iPhone 17 Pro. The
connected Mac hold remains unchanged. No rerun, paid service, cache, release
creation, signing, store upload or publication is introduced. Full artifacts
retain the 500,000,000-byte cap and one-day retention.

The private zero-extra-spend verification is the observed 18:49 UTC receipt,
SHA256 `908122aa7b1421fb693b7424568802eb692ce38e73f8b0f71b422343d6c672f2`.
It is a historical billing observation, not guaranteed current headroom. Root
must check current cost, ownership and time before binding. Quota refusal is
failure and never authorizes spending.

Current Apple upload minimums are Xcode 26 / iOS 26 SDK; Xcode 27 is a separate
latest-platform check, not today's mandatory minimum. Neither this workflow
nor an unsigned archive proves signing, store upload, App Review, public release,
physical-device accessibility or a complete visual audit.

Root authorization remains `UNBOUND`. Pure cloud fixtures and file inspection
do not invoke native tools. V6 controls, failed originals and prior receipts
remain preserved; the prior README is retained under Review.

## Unpublished V7 correction

The sealed V7 draft was never authorized or run. Independent review found a
stray unary plus in its production-included result expression, converting a
Boolean to integer 1 and preventing strict acceptance. V8 removed that one
operator and verifies the actual main-result expression and final gate with a
focused regression. All operational and evidence behavior described above
was introduced in V7 and corrected in V8; the failed draft and review history are preserved.


## V9: installed Xcode 26.6 and preparation evidence

Published V8 run 44379786419 failed before READY: the unchanged 60-second `xcrun simctl list runtimes --json` command timed out. Native tests and archive did not start; the terminal artifact API returned zero. The old diagnostics route required READY, so it skipped this failure. No CoreSimulator cause is claimed.

This separately reviewed candidate uses `/Applications/Xcode_26.6.app/Contents/Developer`, exact build `17F113`, while retaining both iOS 26.5 SDKs, runtime 26.5/23F77 and iPhone 17 Pro. Its own job must verify the exact Xcode, bundled Swift 6.3, both SDK versions, runtime availability/build/ARM64 support and device support. The runtime inventory timeout remains 60 seconds. Apple's Xcode 26.6 release notes and system-requirements matrix document Swift 6.3 and the iOS 26.5 SDK, so unchanged source 02c7 selects its legacy FoundationModels compiler branch. That is compatibility rationale, not a native compilation pass.

An early diagnostic marker is written only after the existing hosted context, authorization and cost checks. It binds the exact plan, source, cost and current run; it cannot substitute for READY. Native execution and full collection still require the original READY and sealed-stage validation. Command start records and terminal statuses are retained; a timeout stores the exact captured stdout/stderr prefix with byte lengths, hashes, base64 encoding and explicit incompleteness, capped at 2 MiB per stream. No environment or credentials are dumped. A diagnostic route before READY rejects any native invocation/output. Its separate artifact keeps the existing 20 MB raw/ZIP caps, stable-descriptor/path/membership and CRC verification, and always reports false for native/full acceptance. The final workflow gate remains unchanged.

The original 190 source / 120 native files, all 69 unit + 21 UI identities/assertions, native 75 minutes / outer 90 minutes, 5400-second launch admission, test 2700 seconds, archive 900 seconds, failed-test archive skip, post-cleanup source verification, complete artifact 500 MB cap, strict late-member rejection and post-pack equality are retained. This preparation/platform revision does not claim to repair V6's five observed UI failure events.

Primary references: https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes and https://developer.apple.com/xcode/system-requirements/ . Exact hosted inventory source: HalalTag run 44378597269, original artifact SHA256 24dffe69f1802750e3d41fe6c944087fe85f0417ffe18fb9914c54fb462331ed. A different app's inventory is supporting evidence only; this Lumina job checks its own platform.
