# Building

## 1. Clone

Clone the repo to a working directory

## 2. Dependencies

To build and configure the libraries Signal uses, just run:

```
make dependencies
```

If the above fails to run, or you just want to know more about our
dependency management systems, read the next section, Dependency Details.
Else if the above completed without error - jump ahead to step 3.

### Dependency Details

We have a couple of dependency management tools. We us Carthage for
managing frameworks, but because some of our dependencies are not yet
framework compatible, we use Cocoapods to manage the remainder in a
static library.

2.1) [CocoaPods](http://cocoapods.org) is used to manage the dependencies in our static library. Pods are setup easily and are distributed via a ruby gem. Follow the simple instructions on the website to setup. After setup, run the following command from the toplevel directory of Signal-iOS to download the dependencies for Signal-iOS:

```
pod install
```

If you are having build issues, first make sure your pods are up to date

```
pod repo update
pod install
```

Occasionally, CocoaPods itself will need to be updated. Do this with

```
gem update cocoapods
pod repo update
pod install
```

2.2) Framework dependencies are built and managed using [Carthage](https://github.com/Carthage/Carthage). Our prebuilt WebRTC.framework also resides in the Carthage/Build directory.

If you don't have carthage, here are the [install instructions](https://github.com/Carthage/Carthage#installing-carthage).

Once Carthage is installed, run:

```
// DO NOT run: `carthage update` or `carthage checkout`.
git submodule update --init
carthage build --platform iOS
```

### Building WebRTC

A prebuilt version of WebRTC.framework resides in our Carthage submodule
and should be installed by the above steps.  However, if you'd like to
build it from source, see: https://github.com/WhisperSystems/signal-webrtc-ios

## 3. XCode

Open the `Signal.xcworkspace` in Xcode.

```
open Signal.xcworkspace
```

In the Signal target on the General tab, change the Team drop down to
your own. You will need an Apple Developer account for that. On the
Capabilities tab turn off Push Notifications and Data Protection. Only
Background Modes should remain on.

Build and Run and you are ready to go!

## Known issues

Features related to push notifications are known to be not working for
third-party contributors since Apple's Push Notification service pushes
will only work with Open Whisper Systems production code signing
certificate.

If you have any other issues, please ask on the [community forum](https://whispersystems.discoursehosting.net/).

