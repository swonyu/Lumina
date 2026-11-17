# Arabic decimal formatting: observed R11 failure

Status: source repair prepared; native retest is pending.

The root coordinator observed the frozen `74fef9d156edd897e3553112ea7ff63b03611320`
run `20261117T143610Z-88793-9244213d5d` fail
`testArabicDecimalDraftPersistsAcrossAppLanguagesOnEnglishDevice` at its
unchanged line-1842 assertion: the saved weight field contained `12.5`, while
the Arabic app choice required `12٫5`. The run was still in progress when the
failure was reported; no aggregate result is claimed here.

The journey entered `١٢٫٥`, retained that unsaved string through an app-language
change, saved it, selected Arabic, relaunched on an English-region device and
opened the saved workout. The failure is in reopened formatting, not evidence
that the stored Double or the original Arabic draft was lost.

`LocalRecordDraft.numberText` uses the selected app locale's decimal separator.
`AppLanguage.arabic.locale` previously returned language-only `ar`. That locale
does not guarantee Arabic numeric symbols: CLDR lists `latn` as its default
numbering system and `arab` as its native alternative. Existing unit coverage
used regional `ar_SA`, so it did not check the actual app locale that failed.

The Arabic app locale now explicitly selects `ar-u-nu-arab`. Its language choice
and saved `ar` preference are unchanged. This sets the numbering system without
substituting a country or calendar. English remains unchanged. Numeric parsing
still accepts both decimal marks and preserves unsaved text through a live
language change; no draft, saved value, test expectation or native assertion is
rewritten.

The existing localization and saved-record unit methods now also assert the
actual app locale's numbering system/decimal separator and the exact `12٫5`
format. All previous assertions remain. There are still 62 unit methods and
21 UI methods after the preceding photo-error regression was added.

Primary references checked during diagnosis:

- [Apple Locale numberingSystem](https://developer.apple.com/documentation/foundation/locale/numberingsystem-swift.property)
- [Apple Locale.Components numberingSystem](https://developer.apple.com/documentation/foundation/locale/components/numberingsystem)
- [Unicode Arabic number formats](https://www.unicode.org/cldr/charts/49/verify/numbers/ar.html)
- [Unicode CLDR numbering-system locale identifiers](https://www.unicode.org/reports/tr35/tr35-numbers.html)

The successor native package must bind this later source commit, retain the
complete 83-case inventory, rerun the observed failing journey and finish the
remaining acceptance gates. The frozen R11 source, runner and result evidence
are not changed by this repair.
