# Building

## 1. Clone

Clone the repo to a working directory

## 2. Depenencies

### tldr;

Build and configure dependencies.


```
make dependencies
```

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

occasionally, CocoaPods itself will need to be updated. Do this with

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

## 3. XCode

Open the `Signal.xcworkspace` in Xcode.

```
open Signal.xcworkspace
```

In the Signal target on the General tab, change the Team drop down to
your own. On the Capabilities tab turn off Push Notifications and Data
Protection. Only Background Modes should remain on.

Some of our build scripts, like running tests, expect your Derived
Data directory to be `$(PROJECT_DIR)/build`. In Xcode, go to `Preferences-> Locations`,
and set the "Derived Data" dropdown to "Relative" and the text field
value to "build".

Build and Run and you are ready to go!

## Known issues

Features related to push notifications are known to be not working for third-party contributors since Apple's Push Notification service pushs will only work with Open Whisper Systems production code signing certificate.

If you have any other issues, please ask on the [community forum](https://whispersystems.discoursehosting.net/).

### Building WebRTC

A prebuilt version of WebRTC.framework resides in our Carthage submodule (see above).
However, if you'd like to build it from souce, this is how it's done.

These instructions are derived from the WebRTC documentation:

https://webrtc.org/native-code/ios/

    # 1. Install depot tools
    cd <somewhere>
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
    cd depot_tools
    export PATH=<somewhere>/depot_tools:"$PATH"
    # 2. Fetch webrtc source
    cd <somewhere else>
    mkdir webrtc
    cd webrtc
    fetch --nohooks webrtc_ios
    gclient sync
    # 3. Build webrtc
    cd src
    tools-webrtc/ios/build_ios_libs.sh
    # 4. Move the WebRTC.framework into Signal-iOS's Carthage directory
    mv out_ios_libs/WebRTC.framework <Your Signal-iOS repository>/Carthage/Build/iOS/

