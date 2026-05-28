# build-bible-db

Converts OSIS XML Bible exports into the JSON shape the Jerusalem app's
`BibleSeeder` reads.

The repo ships with `Sources/Jerusalem/Resources/bible-starter.json` — a tiny
seed dataset (John 3, Psalm 23, Rom 8:28, Phil 4:13 in KJV + WEB) sufficient
for the Phase 7 gate. When you're ready with full translations, drop the OSIS
XML files anywhere on disk and run this tool to regenerate the bundled JSON.

## Where to get public-domain OSIS files

- **KJV**: the SWORD Project / CrossWire (`https://www.crosswire.org/sword/`)
  hosts a public-domain KJV OSIS export.
- **WEB**: the World English Bible (`https://ebible.org/`) publishes OSIS XML
  releases.
- A maintained mirror with both: <https://github.com/seven1m/open-bibles>.

Pick the cleanest OSIS export you can find. The importer handles both the
wrapped (`<verse osisID="...">text</verse>`) and milestone
(`<verse sID/> text <verse eID/>`) forms.

## Usage

From the repo root:

```sh
swift Tools/build-bible-db/main.swift \
    kjv:"King James Version":/path/to/kjv.osis.xml \
    web:"World English Bible":/path/to/web.osis.xml \
    > Sources/Jerusalem/Resources/bible-starter.json
```

Each argument is `id:displayName:path` — the `id` is what `BibleSeeder`
stores in `BibleVerse.translation` (lowercase, free-form), and the
`displayName` is what the editor shows in the translation picker.

Rebuild the app (`xcodegen generate && xcodebuild …`) and the new corpus
ships in the bundle.

## What's handled

- Protestant 66-book canon (apocrypha is skipped with a note on stderr).
- Inline markup inside verses — `<note>`, `<reference>`, `<rdg>` blocks are
  dropped so footnotes don't end up on slides.
- Verse spans in `osisID` (e.g. `Gen.1.1 Gen.1.2`) — the first ID wins.

## What isn't (yet)

- Footnote / cross-reference *inclusion*. If you want them displayed, that's
  a follow-up.
- Title superscripts (the Hebrew Bible book titles, Psalm titles, etc.).
- Variant readings beyond first-child.
