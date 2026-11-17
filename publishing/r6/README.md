# Preserved Lumina R6 candidate

This directory records the exact Mac-prepared Successor-v7-R6-OptionalEffort candidate. The repository root contains all119 Source files with identical SHA256 hashes; seven existing bilingual support/privacy-site files remain unchanged. The integration starts from251f5c18b1526369246338c269c4af3bea7061ca, which already contains all three pinned published Lumina branch heads. Nothing from the separate legacy LuminaCoach repository is used.

## Verification boundary

R6 is preserved for audit, not accepted as release-ready. Root reported real R6 native failures while this composition was in progress: two export-picker crashes in SwiftUI AnyTransferable/FileWrapper, two integrity tests with three failed expectations, Arabic coach provenance visibility failure before the language persistence stage, and a Privacy link reachability failure at largest text. The remaining native suite and archive status must be read from the root-owned native receipt. Do not relabel this candidate as passing based on source parity.

The original prepared-successor receipt says PREPARED_ONLY_NATIVE_NOT_RUN because it records preparation time. It is intentionally retained unchanged as historical evidence; it does not override later native failures. Any correction belongs to a distinct successor commit and native run, with all existing assertions retained.

## Inputs and preservation

- Source manifest SHA256:c0bae4ffdb3ac74d3f896145cc29e665444fdc75c85ce0064e15e934c47ce4af.
- Runner SHA256:7431ba3fa0d30eaf939f440a468aca25808ea954aec64833c24b2a0ee6f1bd4f.
- Artifact verifier SHA256:d91a60b51ab9c1bb959157f9dfe82c3645beb952ede80303d541d6d15ebe718b.
- R6 expects61 unit and18 selected UI tests (79 total). Source composition is not native execution.
- The manifest also references a separate advertising-preparation root which was not transferred or integrated. No advertising SDK, ad service or paid request is introduced.
- Original repository files remain in parent Git history, and pre-composition-receipt.json pins their bytes and executable modes. There were no source deletions. Existing CI shell executable modes are retained.
- Top-level README and release notes are exact R6 source, including explicitly marked historical setup text. The current no-cloud/no-paid-coach behavior is described in FREE_LOCAL_RELEASE.md; source parity does not establish device model availability or answer quality.

The copied runner and artifact verifier retain their original paths/source guards. They must not be executed against a different candidate by altering a pin or suppressing a failure. Their presence is provenance, not a new scheduled build or CI job. No Mac files, native locks, processes, signing configuration or store submission were changed by this cloud composition.
