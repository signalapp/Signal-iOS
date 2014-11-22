# Signal for iOS [![Build Status](https://travis-ci.org/WhisperSystems/Signal-iOS.svg?branch=master)](https://travis-ci.org/WhisperSystems/Signal-iOS)
[![Gitter](https://badges.gitter.im/Join Chat.svg)](https://gitter.im/WhisperSystems/Signal-iOS?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

Signal allows you to make private phone calls and we are working on bringing secure messaging to it soon.

[![Available on the AppStore](http://cl.ly/WouG/Download_on_the_App_Store_Badge_US-UK_135x40.svg)](https://itunes.apple.com/app/id874139669)

## Building

While you can build Signal from this repo it will not be possible to use it without your code being signed using the Whisper Systems certificate (which is only available to core devs). The reason for this is that the (currently) required push notifications can only be sent to apps which have been signed by the key owned by the sender. There is currently no workaround. If you want to use rather than study Signal then please download from the App Store.

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

3) Open the `Signal.xcworkspace` in Xcode. Build and Run and you are ready to go!

## Translation

Help us translate Signal! The translation effort happens on [Transifex](https://www.transifex.com/projects/p/signal-ios/)

## Interoperability 

Signal works with [RedPhone on Android](https://github.com/WhisperSystems/Redphone).

## Cryptography Notice

This distribution includes cryptographic software. The country in which you currently reside may have restrictions on the import, possession, use, and/or re-export to another country, of encryption software. 
BEFORE using any encryption software, please check your country's laws, regulations and policies concerning the import, possession, or use, and re-export of encryption software, to see if this is permitted. 
See <http://www.wassenaar.org/> for more information.

The U.S. Government Department of Commerce, Bureau of Industry and Security (BIS), has classified this software as Export Commodity Control Number (ECCN) 5D002.C.1, which includes information security software using or performing cryptographic functions with asymmetric algorithms. 
The form and manner of this distribution makes it eligible for export under the License Exception ENC Technology Software Unrestricted (TSU) exception (see the BIS Export Administration Regulations, Section 740.13) for both object code and source code.

## License

Copyright 2014 Open Whisper Systems

Licensed under the GPLv3: http://www.gnu.org/licenses/gpl-3.0.html
