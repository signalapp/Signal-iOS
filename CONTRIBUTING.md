# Contributing to Session iOS

Thank you for supporting Session and looking for ways to help. Please note that some conventions here might be a bit different than what you are used to, even if you have contributed to other open source projects before. Reading this document will help you save time and work effectively with the developers and other contributors.

## Where do I start?

The bulk of the Session code can be found under Signal/src/Loki and SignalServiceKit/src/Loki.


## Development ideology

Truths which we believe to be self-evident:

1. **The answer is not more options.**  If you feel compelled to add a preference that's exposed to the user, it's very possible you've made a wrong turn somewhere.
1. **The user doesn't know what a key is.**  We need to minimize the points at which a user is exposed to this sort of terminology as extremely as possible.
1. **There are no power users.**  The idea that some users "understand" concepts better than others has proven to be, for the most part, false. If anything, "power users" are more dangerous than the rest, and we should avoid exposing dangerous functionality to them.
1. **If it's "like PGP," it's wrong.**  PGP is our guide for what not to do.
1. **It's an asynchronous world.**  Be wary of anything that is anti-asynchronous: ACKs, protocol confirmations, or any protocol-level "advisory" message.
1. **There is no such thing as time.**  Protocol ideas that require synchronized clocks are doomed to failure.


## Issues

Please search both open and closed issues to make sure your bug report is not a duplicate.

### Open issues

#### If it's open, it's tracked
The developers read every issue, but high-priority bugs or features can take precedence over others. Session is an open source project, and everyone is encouraged to play an active role in diagnosing and fixing open issues.

### Closed issues

#### "My issue was closed without giving a reason!"
Although we do our best, writing detailed explanations for every issue can be time consuming, and the topic also might have been covered previously in other related issues.


## Pull requests

### Smaller is better
Big changes are significantly less likely to be accepted. Large features often require protocol modifications and necessitate a staged rollout process that is coordinated across millions of users on multiple platforms (Android, iOS, and Desktop).

Try not to take on too much at once. As a first-time contributor, we recommend starting with small and simple PRs in order to become familiar with the codebase. Most of the work should go into discovering which three lines need to change rather than writing the code.

### Submit finished and well-tested pull requests
Please do not submit pull requests that are still a work in progress. Pull requests should be thoroughly tested and ready to merge before they are submitted.

### Merging can sometimes take a while
If your pull request follows all of the advice above but still has not been merged, this usually means that the developers haven't had time to review it yet. We understand that this might feel frustrating, and we apologize.


## How can I contribute?
There are several other ways to get involved:
* Help new users learn about Session.
  * Redirect support questions to support@loki.network.
* Improve documentation in the [wiki](https://github.com/loki-project/session-protocol-docs/wiki).
* Find and mark duplicate issues.
* Try to reproduce issues and help with troubleshooting.
* Discover solutions to open issues and post any relevant findings.
* Test other people's pull requests.
* Share Session with your friends and family.

Session is made for you. Thank you for your feedback and support.
