# Translations

Translations are solicited on Transifex[https://www.transifex.com/]. We
upload our source language (US English) to Transifex, where our
translators can submit their translations. Before the app is released,
we pull their latest work into the code base.

## Fetch

You should always fetch the latest translations before pushing new
source translations, as any newly updated source strings will blow away
the existing translated strings. Generally when a source string is
updated, it's preferred to have the previous translation vs an english
string.

To fetch the latest translations:

    bin/pull-translations

This imposes some limits on what localizations we include. For example,
we don't want to include languages until a substantial portion of the
app has been translated.

## Source Strings

Run `bin/auto-genstrings` to extract the latest translatable strings and
comments from our local files (Signal-iOS and SignalServiceKit). The
script assumes Signal-iOS and SignalServiceKit have the same parent
directory. e.g. `~/src/Signal-iOS` and `~/src/SignalServiceKit`

### Writing Good Translatable Strings

Be sure to add a comment to provide context to the translators. For
example:

    /* Tab button label which takes you to view all your archived conversations */
    ARCHIVE_HEADER="Archive"
    /* Button label to archive the current conversation */
    ARCHIVE_ACTION="Archive"

Be sure to include comments in your translations, and enforce that other
contributors do as well.  Why comment? For example, in English these are
the same, but in Finnish the noun/verb are distinct.

    /* Tab button label which takes you to view all your archived conversations */
    ARCHIVE_HEADER="Arkisto"

    /* Button label to archive the current conversation */
    ARCHIVE_ACTION="Arkistoi"

Context should also provide a hint as to how much text should be
provided. For example, is it an alert title, which can be a few words, a
button, which must be *very* short, or an alert message, which can be a
little longer?

### Upload

Make new source strings available to our translators by uploading them
to transifex. Make sure you've fetched the latest translations first,
otherwise you could overwrite some useful translations on Transifex.

    tx push --source

