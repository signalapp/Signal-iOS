Apart from the general `BUILDING.md` there are certain things that have
to be done by Signal-iOS maintainers.

For transperancy and bus factor, they are outlined here.

## Dependencies

Keeping cocoapods based dependencies is easy enough.

`pod update`

### WebRTC

We don't currently have an automated build (cocoapod/carthage) setup for
the WebRTC.framework. Instead, read the WebRTC upstream source and build
setup instructions here:

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

## Translations

Read more about translations in [TRANSLATIONS.md](signal/translations/TRANSLATIONS.md)
