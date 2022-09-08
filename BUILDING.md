# Building

We typically develop against the latest stable version of Xcode.

## 1. Clone

Clone the repo to a working directory:

```
git clone --recurse-submodules https://github.com/signalapp/Signal-iOS
```

Since we make use of sub-modules, you must use `git clone`, rather than
downloading a prepared zip file from Github.

We recommend you fork the repo on GitHub, then clone your fork:

```
git clone --recurse-submodules https://github.com/<USERNAME>/Signal-iOS.git
```

You can then add the Signal repo to sync with upstream changes:

```
git remote add upstream https://github.com/signalapp/Signal-iOS
```

Another way to clone the repo is by using Xcode:

When first opening Xcode choose the 'Clone an existing project' option

![Signal Message](https://drive.google.com/uc?export=view&id=1nH6Yp-9h_aEd1N82Jv2vZhvGmCXJbnKf =400x350)

Then, paste the repo's GitHub link (https://github.com/signalapp/Signal-iOS.git) into the navigation bar on the popup window and click the 'Clone' button on the bottom right corner

![Signal Message](https://drive.google.com/uc?export=view&id=1kvi4hUiCVKAWzoIYJ8hI4T1X3UgUfsAk =500x320)

Finally, choose which branch to check out and hit the 'Clone' button

![Signal Message](https://drive.google.com/uc?export=view&id=1VXq34OFxEGE5Fm4K7ZjLDvhlVgateuD9 =500x310)

## 2. Dependencies

To build and configure the libraries Signal uses, just run:

```
make dependencies
```

Make sure to run this command within the working directory where you cloned the repo.

### Building RingRTC

A prebuilt version of WebRTC.framework and the libringrtc static library reside
in a sub-module and should be installed by the above steps. However, if you'd
like to build it from source, see: https://github.com/signalapp/ringrtc

## 3. Xcode

Open the `Signal.xcworkspace` in Xcode.

```
open Signal.xcworkspace
```

In the TARGETS area of the General tab, change the Team drop down to
your own. You will need to do that for all the listed targets, for ex.
Signal, SignalShareExtension, and SignalMessaging. You will need an Apple
Developer account for this.

On the Capabilities tab, turn off Push Notifications and Data Protection,
while keeping Background Modes on. The App Groups capability will need to
remain on in order to access the shared data storage. The App ID needs to
match the `applicationGroup` string set (both Production and Staging) in TSConstants.swift.

If you wish to test the Documents API, the iCloud capability will need to
be on with the iCloud Documents option selected.

Build and Run and you are ready to go!

## Known issues

Features related to push notifications are known to be not working for
third-party contributors since Apple's Push Notification service pushes
will only work with Open Whisper Systems production code signing
certificate.

Turn on Push Notifications on the Capabilities tab if you want to register a new Signal account using the application installed via XCode.

If you have any other issues, please ask on the [community forum](https://whispersystems.discoursehosting.net/).
