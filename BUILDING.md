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

3) Some dependencies are added via carthage. Run:
```
carthage update
```
If you don't have carthage, here are install instructions:

```

https://github.com/Carthage/Carthage#installing-carthage

```

4) We don't currently have an automated build (cocoapod/carthage) setup for
the WebRTC.framework and we need the libraries for a successful XCode build. 
Instead, read the WebRTC upstream source and build setup instructions here:

https://webrtc.org/native-code/ios/

Once you have your build environment set up and the WebRTC source downloaded:

    # The specific set of commands that worked for me were somewhat different.
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
    # NOTE: build_ios_libs.sh only worked for me from inside "src"
    cd src
    webrtc/build/ios/build_ios_libs.sh
    # NOTE: It's Carthage/Build/iOS, not Carthage/Builds
    mv out_ios_libs/WebRTC.framework ../../Signal-iOS/Carthage/Build/iOS/


5) Open the `Signal.xcworkspace` in Xcode.

```
open Signal.xcworkspace

```

6) In the Signal target on the General tab, change the Team drop down to your own. On the Capabilities tab turn off Push Notifications and Data Protection. Only Background Modes should remain on.

7) Some of our build scripts, like running tests, expect your Derived
Data directory to be `$(PROJECT_DIR)/build`. In Xcode, go to `Preferences-> Locations`,
and set the "Derived Data" dropdown to "Relative" and the text field
value to "build".

8) Build and Run and you are ready to go!

## Known issues

Features related to push notifications are known to be not working for third-party contributors since Apple's Push Notification service pushs will only work with Open Whisper Systems production code signing certificate.

If you would like to contribute a transation please read the MAINTAINING.md file in this directory.

