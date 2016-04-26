# Translations

Translations are solicited on transifex.

### Fetch

Fetch the latest translations from transifex.

    bin/pull-translations

### Upload

Upload new translation source (make sure you've fetched the latest
translations first, otherwise you could irrevocably overwrite our
translations on transifex.

    bin/push-source

### Announce

After uploading all possible source translations, solicit any new
translations we'll need before releasing. e.g. by using the Transifex
announcement tool or on the forum.


### TODO

Some of the new German translations are much longer than before. Verify
they don't break layout.
