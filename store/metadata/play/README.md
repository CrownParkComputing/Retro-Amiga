# Play Store metadata

Google Play only. The files under `store/metadata/version/` and
`store/metadata/app-info/` are App Store Connect's, uploaded by
`tools/appstore/asc.rb`, and Apple's fields do not map onto Play's.

## whatsnew-en-GB.txt

Pasted into the release's "What's new in this release?" box. Play caps this
at 500 characters per language; `wc -m` before pasting.

Worth knowing when writing these: a release that drops device support - the
64-bit-only change did, by 5,812 devices - is announced by Play itself on the
store listing, but only to users it affects. Saying so in the notes as well is
what stops it reading as an app that silently stopped working.
