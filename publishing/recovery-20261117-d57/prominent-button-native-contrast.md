# Prominent button contrast repair

## Actual failure and recovered evidence

Frozen R11 commit `74fef9d156edd897e3553112ea7ff63b03611320` ran on the Mac in
`20261117T143610Z-88793-9244213d5d`. The run timed out during UI acceptance;
its incomplete `UIQATests.xcresult` has no `Info.plist`, so ordinary result
parsing failed. No file in that original result bundle was changed.

The completed UI output records twelve passing cases and two failing cases:
the Arabic reopened decimal formatting assertion and the optional-nutrition
contrast audit. The recovery journey started but was interrupted. A separate
raw unit diagnostic explicitly records **61 tests in nine suites passed**.
That diagnostic does not turn an interrupted, failing UI run into acceptance.
The parser's exit code 64 is an error code, not a test count.

The contrast failure is at `LuminaUITests.swift:1268`, during the first full
contrast audit of the English empty meal-name form. The failure describes
insufficient contrast for a SwiftUI accessibility node. Its actual element
screenshot and the surrounding session log identify the **Save Meal button**,
`lumina.meal.new-save`, at `(15.8, 493.4, 370.5, 52.8)` points. It is not a
meal text-field failure. The recorded screen shows white headline text over
the original bright system blue-to-purple gradient.

The screenshot payloads were recovered byte-for-byte from the incomplete
result's `Data` store. The field-tree payload was decompressed with the
already-installed `zstd`, entirely in memory. The files under `r11-native/`
contain the original pre-audit screen, the failure's element screenshot, the
AX tree, a source/attachment hash record, and the unit diagnostic's exact
passing-test lines. These are real failed-run evidence, not generated UI.

## Product change

`GlassButton` now uses opaque sRGB `#1F4EB4` and `#6331A5` for its prominent
gradient. These remain blue and purple while providing more contrast with
the existing white label. Their calculated white-text contrast ratios are
7.481:1 and 8.356:1. This calculation guides the palette; the real native
contrast audit remains the acceptance test.

W3C's contrast guidance explains the relative-luminance calculation and
4.5:1 threshold for ordinary text, and recommends additional margin where
rendering can reduce apparent readability:
https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html

The same prominent component is used by meal, workout, and check-in saves
and several older components. Its headline font, white foreground, layout,
padding, shape, border, action, enabled state, accessibility identity, and
non-prominent material style are unchanged. The opaque palette also avoids
background-dependent transparency under the text. Native Arabic, Dynamic
Type, and whole-screen audits still need to run on the updated source.

## Verification boundary

This is a separate change on top of `b30f1188368435c210ca589db994daab5ca2cd50`,
which already contains the retained photo-error localization fix and the
explicit Arabic numbering-system repair. No test or assertion was removed,
filtered, enlarged, hidden, or otherwise changed for this contrast repair.
`LuminaUITests.swift` remains byte-for-byte identical to frozen R11. Its
English/Arabic empty/populated meal audits and largest-text journeys remain
the regression coverage.

The successor retains **62 unit cases plus all 21 UI cases (83 total)**.
Its already-reviewed runner uses a 2,300-second test-step ceiling within the
same 45-minute overall window and 120-second cleanup reserve. Source,
runner, and test-inventory checks are preparation evidence only. This
repair has not yet been compiled, native-tested, installed as production,
submitted, or released by this agent.
