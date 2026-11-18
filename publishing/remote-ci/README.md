# Lumina isolated native verification proposal

This control package runs the reviewed Lumina candidate on a fresh standard
GitHub-hosted `macos-26` VM. The candidate source and this workflow control commit
are recorded separately. The package does not use the connected Mac, its native
schedule, owners, claims, ACKs, or priority hold.

**Native acceptance remains unverified.** `candidate.json` binds the exact
reviewed candidate commit/tree and source inventories. The root coordinator must
bind fresh authorization for one isolated GitHub-hosted attempt in `root-review.json`;
this proposed package remains unbound and cannot start native work. `inspect` validates files only and
cannot create a simulator, lock or native job.

## Preserved gates

- The distinct remote-v4 runner SHA is
  `63bef510ab0b493b2f6b61a73042ccdcd3b347758d13df3ae9540ff881c471c4`.
  Its verified public `publishing/r8` baseline and exact changes are recorded
  below; it is not the unavailable `a4ad9a5a` runner.
- All 190 candidate Git blobs and modes are checked before materializing the
  exact 120 native inputs. Executable CI hooks retain mode `100755`.
- The full 69 unit and 21 UI cases run once. No focused filters, skipped
  production archive, test retries or workflow rerun attempts are accepted.
- The planned 45-minute batch, 2,300-second test, 900-second archive and
  120-second cleanup limits remain. The outer job leaves
  additional time for preparation and complete evidence transfer.
- Xcode 26.5 / build 17F42, iOS 26.5 SDK/runtime and iPhone 17 Pro are checked in
  the actual VM. This environment differs from historical local simulator runs.
- The unsigned production archive invokes the actual
  `Source/ci_scripts/verify_release_archive.py`. No signing key or account is
  required or supplied; this is not store distribution or release evidence.

## Evidence and costs

The root coordinator verified a zero-extra-spend policy. Only its private
receipt hash and minimal operational constraints are published here, with no
account billing details. The job uses public standard compute, no cache or paid
runner, one-day artifact retention and a conservative 500,000,000-byte complete
evidence cap. A quota, size or upload refusal fails acceptance. Neither full
xcresults nor screenshots are shortened or removed to fit the quota.

The archive contains the candidate sources, complete staged inputs, raw native
results, raw xcresults, original screenshot/AX attachments, unsigned
archive, settings, verifier output, logs, source checks, modes and integrity
index. The only Git metadata exclusion is the exact `Candidate/.git` subtree.
Five named reproducible cache categories may be omitted only beneath the
runner's four declared Lumina derived lanes: `Build`,
`SDKExplicitPrecompiledModules`, `ModuleCache.noindex`, `SDKStatCaches.noindex`
and `CompilationCache.noindex`. Every omission is indexed with its path, size,
hash or link target, and mode. Original `.xcresult`/`.xcarchive`, raw logs,
`Logs`/`TestResults`, and unknown paths remain included even when nested there.
Historical R19 sizing showed about 252 MB of required native evidence after
these exclusions; the actual current bundle must still pass the size gate.
No native evidence is deleted from the VM. The
source artifacts and failed/interrupted output remain intact in the VM; no
cleanup deletes evidence. A failed native job still attempts evidence retention
if preparation and the cost policy passed. An invalid, truncated, duplicate-key,
wrong-shaped or missing native report yields a failed verdict while originals
are still packaged for review.

The artifact upload receipt and the inner tar SHA are distinct. A successful job
does not claim evidence has been downloaded or its original screenshots have
been reviewed. The root coordinator must download within the one-day retention,
verify the tar digest and all indexed members, and review the actual UI before
using this result as release evidence.

## Review commands

These commands are file-only. The contract checks import pure runner guards
and replace every native entry point with fixtures; they do not create a
simulator, acquire a lock, launch Xcode, or claim native acceptance:

```sh
python3 publishing/remote-ci/remote_ci.py inspect --control-root .
python3 -B -m unittest discover -s publishing/remote-ci -p test_remote_ci.py -v
LUMINA_REVIEW_SOURCE=/absolute/path/to/verified/R23/source python3 -B -m unittest discover -s publishing/remote-ci -p test_remote_runner.py -v
```

The `prepare`, `run` and `collect` modes reject non-hosted environments. Future
invocation also requires the exact continuation branch, public repository,
bound source, root review receipt and the original user deadline
`2026-11-18T22:26:12Z`. A branch-scoped push is proposed because initial manual
dispatch requires default-branch workflow availability; no default branch change
is included.

## Historical v3 recovery successor

The accepted v2 package could not run because its 81,426-byte `a4ad9a5a` runner had not yet been recovered from the Mac when v3 was prepared. The six frozen JSON inputs were recovered with exact v2 hashes; all 190 R22 Git blobs and modes were independently verified. V3 is explicitly a different runner. Its baseline is the public R22 tree's `publishing/r8/Runner/verify_publishing.py`, 77,910 bytes, SHA256 `0e7af7af455b34b1b90606f7412d4cb57fbdcee58c2953191e2d21e05bafd109`. The reviewed delta adds the eight missing current unit identities, retains all 21 UI identities, uses the already planned 2,300-second test limit, and sets `full_test_gate_passed` only after exact case proof. The initial scope fields declare the intended full plan and do not claim a pass. Its entry guard rejects local, partial, skipped-production, reused-attempt, or out-of-stage invocations. The inherited settings, archive/verifier, source inventory, process ownership, simulator cleanup and lock lifecycle functions are preserved. The full v3 SHA is `34e08ce5750862748f22fef8b39f347cf2d480fca7a847540c41254ca0d0cf9b`. That v3 control ran as `44342327548`, attempt 1, and failed before any test executed because its R22 coach generator used APIs absent from the iOS 26.5 SDK. The complete original failed-run artifact was downloaded and verified; its production archive also failed.


## R23 compatibility successor and remaining release gate

V4 binds source `02c7cfc11cd8b6049e67cc0d767079363d8aa6ca`, tree `31a9678032b666414d44d9691e64908f850f2108`,
on the distinct `continuation/publishing-r23-remote-ci-d57` control branch. Exactly one of
190 app files changes: the coach generator selects the correct SDK initializer
and error contract while preserving all typed safety and fallback mappings.
All 69 unit and 21 UI test bodies and identities remain unchanged.

The runner's only execution change from v3 is the exact new branch guard. Its
revision label and review text change accordingly; the wrapper pins that new
runner. The same Xcode 26.5 lane first verifies the observed compilation repair
and requires the complete native suite, unsigned archive and original evidence.
This verification does not establish App Store submission readiness. Apple's
[current Foundation Models error documentation](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror)
requires adoption of the Xcode 27 error contract before submission. A separately
reviewed current-SDK distribution lane and actual store evidence remain required.

The failed v3 run must not be rerun. Only the separately reviewed v4 control may
start a new first attempt. Root authorization must also recheck current free
included-storage headroom and the unchanged zero-dollar spending stop. Every
native, source, archive, ownership, retention and complete-evidence gate above
remains mandatory; no source fix or file-only fixture result is a native pass.
