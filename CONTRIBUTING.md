## Contributor agreement

Apple requires contributors to iOS projects to relicense their code on submit. We'll have to have individual contributors sign something to enable this.

Our volunteer legal have put together a form you can sign electronically. So no scanning, faxing, or carrier pigeons involved. How modern:
https://whispersystems.org/cla/

Please go ahead and sign, putting your github username in "Address line #2", so that we can accept your pull requests at our heart's delight.

## Code Conventions

To get started with developing for Signal iOS, please read [this tutorial on git best practices](https://gist.github.com/corbett/ef9fd5f1abbef3b02f3b).

We are trying to follow the [GitHub code conventions for Objective-C](https://github.com/github/objective-c-conventions) and we appreciate that pull requests do conform with those conventions.

In addition to that, always add curly braces to your `if` conditionals, even if there is no `else`. Booleans should be declared according to their Objective-C definition, and hence take `YES` or `NO` as values.

Any category extension on UIKit, or popular libraries, should be prefixed with `ows_` to avoid collisions.

One note, for programmers joining us from Java or similar language communities, note that [exceptions are not commonly used for errors that may occur in normal use](http://stackoverflow.com/questions/324284/throwing-an-exception-in-objective-c-cocoa/324805#324805) so familiarize yourself with **NSError**.

### UI conventions
We prefer to use [Storyboards](https://developer.apple.com/library/ios/documentation/general/conceptual/Devpedia-CocoaApp/Storyboard.html) vs. building UI elements within the code itself. We are not at the stage to provide a .strings localizable file for translating, but the goal is to have translatable strings in a single entry point so that we can reach users in their native language wherever possible.

## Tabs vs Spaces

It's the eternal debate. We chose to adopt spaces. Please set your default Xcode configuration to 4 spaces for tabs, and 4 spaces for indentation (it's Xcode's default setting).

![Tabs vs Spaces](http://cl.ly/TYPZ/Screen%20Shot%202014-01-26%20at%2019.02.28.png)

If you don't agree with us, you can use the [ClangFormat Xcode plugin](https://github.com/travisjeffery/ClangFormat-Xcode) to code with your favorite indentation style!

## BitHub

Open Whisper Systems is currently [experimenting](https://whispersystems.org/blog/bithub/) with the funding privacy Free and Open Source software. For example, this is the current Open WhisperSystems payout per commit, rendered dynamically as an image by the Open WhisperSystems BitHub instance:

[![Bithub Payment Amount](https://bithub.herokuapp.com/v1/status/payment/commit)](https://whispersystems.org/blog/bithub/)

If you'd like to opt out of receiving a payment, simply include the string "FREEBIE" somewhere in your commit message, and you will not receive BTC for that commit.

## Contributors

Signal wouldn’t be possible without the many open-source projects we depend on. Big shoutout to the maintainers of all the [pods](https://github.com/WhisperSystems/Signal-iOS/blob/master/Podfile) we use!

The original version of Signal was developed by Twisted Oak Studios.
v1.0 development by Twisted Oak Studios:

- Connor Bell (@connorbell)
- Craig Gidney (@strilanc)
- Matthew Jewkes (@mjewkes)
- Petar Markovich (@Waxford)
- Jazz Turner Baggs (@jazzz)

The development from 1.0 to 2.0 of Signal was managed by [Christine Corbett](https://twitter.com/corbett) and [Frederic Jacobs](https://twitter.com/FredericJacobs). After the release of Signal 2.0,  Christine moved on to other projects.

We would like to particularly thank the following people for contributing to Signal 2.0: 

- Tyler Reinhard for his work on Signal 2.0 design
- Cade (@helveticade) for his numerous UX and UI contributions
- Dylan Bourgeois for his work on helping to integrate TextSecure UI into the existing Signal project
- Joshua Lund for the amazing QA work and immensely helpful feedback provided over the months of testing
- Joyce Yan and Jack Rogers for their contributions at the Winter Break of Code
- [Abelard](http://abelard.bandcamp.com/) for the Signal ringtones and notification sounds
