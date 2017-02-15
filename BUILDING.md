## Building

1) Clone the repo to a working directory

2) [CocoaPods](http://cocoapods.org) is used to manage dependencies. Pods are setup easily and are distributed via a ruby gem. Follow the simple instructions on the website to setup. After setup, run the following command from the toplevel directory of Signal-iOS to download the dependencies for Signal-iOS:

```
pod install
```
If you are having build issues, first make sure your pods are up to date
```
pod update
pod install
```
occasionally, CocoaPods itself will need to be updated. Do this with
```
sudo gem update
```

3) Some dependencies are added via carthage. However, our prebuilt WebRTC.framework also resides in the Carthage directory. 

Run:
```
// DO NOT run: `carthage update` or `carthage checkout`.
git submodule update --init
carthage build
```

If you don't have carthage, here are install instructions:
```
https://github.com/Carthage/Carthage#installing-carthage
```

4) Open the `Signal.xcworkspace` in Xcode.

```
open Signal.xcworkspace
```

5) In the Signal target on the General tab, change the Team drop down to your own. On the Capabilities tab turn off Push Notifications and Data Protection. Only Background Modes should remain on.

6) Some of our build scripts, like running tests, expect your Derived
Data directory to be `$(PROJECT_DIR)/build`. In Xcode, go to `Preferences-> Locations`,
and set the "Derived Data" dropdown to "Relative" and the text field
value to "build".

7) Build and Run and you are ready to go!

## Known issues

Features related to push notifications are known to be not working for third-party contributors since Apple's Push Notification service pushs will only work with Open Whisper Systems production code signing certificate.

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

