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

3) Open the `Signal.xcworkspace` in Xcode. Build and Run and you are ready to go!

## Known issues

Features related to push notifications are known to be not working for third-party contributors since Apple's Push Notification service pushs will only work with Open Whisper Systems production code signing certificate.