# Signal for iOS

Signal is a messaging app for simple private communication with friends.

[![Available on the App Store](http://cl.ly/WouG/Download_on_the_App_Store_Badge_US-UK_135x40.svg)](https://itunes.apple.com/us/app/signal-private-messenger/id874139669?mt=8)

# Building

For now you can use the latest Xcode version (10.0 at the moment)

## 0. Prerequisites

Make sure [CocoaPods](https://cocoapods.org/about) and [Carthage](https://github.com/Carthage/Carthage) both installed on your computer. You can install both using [Homebrew](https://brew.sh)
Once you have brew installed, run 2 commands in the Terminal : 

```ruby
brew install cocoapods
```

```ruby
brew install carthage
```

Moreover, ask your colleagues to add you to our Apple developers team.

Once you are done with these steps, move on.

## 1. Clone

Clone our repository using SSH or HTTP

## 2. Dependencies

Before first build run 3 commands inside your local project's folder :

```ruby
pod install
```

```ruby
// DO NOT run: `carthage update` or `carthage checkout`.
git submodule update --init
carthage build --platform iOS
```

## 3. Xcode

For now our project doesn't work with simulators, so you need to build on the real device.
To achieve it make sure you've been added to Apple Developers team and you are logged in with your account inside Xcode.
Then go to the Project tab inside Xcode and set signing to Automatic. Select "LETKNOW HQ COMPANY LIMITED" for both targets : Signal & Signal-ShareExtension. Run on the device.

## Translation

Help us translate Signal! The translation effort happens on [Transifex](https://www.transifex.com/signalapp/signal-ios/)

## Contributing Code

Instructions on how to set up your development environment and build Signal-iOS can be found in [BUILDING.md](https://github.com/signalapp/Signal-iOS/blob/master/BUILDING.md). Other useful instructions for development can be found on the [Development Guide wiki page](https://github.com/signalapp/Signal-iOS/wiki/Development-Guide). We also recommend reading the [contribution guidelines](https://github.com/signalapp/Signal-iOS/blob/master/CONTRIBUTING.md).

## Contributing Ideas
Have something you want to say about Open Whisper Systems projects or want to be part of the conversation? Get involved in the [community forum](https://community.signalusers.org).

## SignalServiceKit

Check out the [SignalServiceKit README](SignalServiceKit/README.md) for
details about using SignalServiceKit in your own app.

## Cryptography Notice

This distribution includes cryptographic software. The country in which you currently reside may have restrictions on the import, possession, use, and/or re-export to another country, of encryption software. 
BEFORE using any encryption software, please check your country's laws, regulations and policies concerning the import, possession, or use, and re-export of encryption software, to see if this is permitted. 
See <http://www.wassenaar.org/> for more information.

The U.S. Government Department of Commerce, Bureau of Industry and Security (BIS), has classified this software as Export Commodity Control Number (ECCN) 5D002.C.1, which includes information security software using or performing cryptographic functions with asymmetric algorithms. 
The form and manner of this distribution makes it eligible for export under the License Exception ENC Technology Software Unrestricted (TSU) exception (see the BIS Export Administration Regulations, Section 740.13) for both object code and source code.

## License

Copyright 2014-2018 Open Whisper Systems

Licensed under the GPLv3: http://www.gnu.org/licenses/gpl-3.0.html
