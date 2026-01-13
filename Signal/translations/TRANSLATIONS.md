# Translations

## For Developers

### Localize User Facing Strings

Use the NSLocalizedString macros to mark any user-facing strings as
localizable. See existing usages of this macro for examples.

### Extract Source Strings

To extract the latest translatable strings and comments from our local source
files into our English localization file:

    bin/auto-genstrings

At this point you should see your new strings, untranslated in only the English
(en) localization.

Edit Signal/translations/en.lproj/Localizable.strings to translate your strings.

Commit these English translations with your work. Do not touch the non-English
localizations. **Those are updated as part of our release process by Signal
Staff.**

### Writing Good Translatable Strings

Be sure to include comments in your translations, and enforce that other
contributors do as well.  Why comment? For example, in English these are
the same, but in Finnish the noun/verb are distinct.

#### English

    /* Tab button label which takes you to view all your archived conversations */
    ARCHIVE_HEADER="Archive"
    
    /* Button label to archive the current conversation */
    ARCHIVE_ACTION="Archive"

#### Finnish

    /* Tab button label which takes you to view all your archived conversations */
    ARCHIVE_HEADER="Arkisto"

    /* Button label to archive the current conversation */
    ARCHIVE_ACTION="Arkistoi"

Context should also provide a hint as to how much text should be
provided. For example, is it an alert title, which can be a few words, a
button, which must be *very* short, or an alert message, which can be a
little longer?
