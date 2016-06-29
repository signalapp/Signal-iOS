#!/bin/sh

# Bitcode is not working

FWNAME="openssl"
OSX_MIN="10.9"
IOS_MIN="8.0"

rm -rf Frameworks/ios/$FWNAME.framework
rm -rf Frameworks/macos/$FWNAME.framework

echo "Creating $FWNAME.framework"
mkdir -p Frameworks/ios/$FWNAME.framework/Headers
mkdir -p Frameworks/macos/$FWNAME.framework/Headers

# xcrun --sdk iphoneos ld -dylib -arch armv7  -bitcode_bundle -ios_version_min $IOS_MIN lib-ios/libcrypto.a -o Frameworks/ios/$FWNAME.framework/$FWNAME-armv7
# xcrun --sdk iphoneos ld -dylib -arch armv7s -bitcode_bundle -ios_version_min $IOS_MIN lib-ios/libcrypto.a -o Frameworks/ios/$FWNAME.framework/$FWNAME-armv7s
# xcrun --sdk iphoneos ld -dylib -arch arm64  -bitcode_bundle -ios_version_min $IOS_MIN lib-ios/libcrypto.a -o Frameworks/ios/$FWNAME.framework/$FWNAME-arm64
# xcrun --sdk iphoneos lipo -create Frameworks/ios/$FWNAME.framework/$FWNAME-* -output Frameworks/ios/$FWNAME.framework/$FWNAME
# rm -rf Frameworks/ios/$FWNAME.framework/$FWNAME-*

xcrun --sdk iphoneos libtool -dynamic -no_warning_for_no_symbols -undefined dynamic_lookup -ios_version_min $IOS_MIN -o Frameworks/ios/$FWNAME.framework/$FWNAME lib-ios/libcrypto.a lib-ios/libssl.a
xcrun --sdk macosx   libtool -dynamic -no_warning_for_no_symbols -undefined dynamic_lookup -macosx_version_min $OSX_MIN -o Frameworks/macos/$FWNAME.framework/$FWNAME lib-macos/libcrypto.a lib-macos/libssl.a

cp -r include-ios/$FWNAME/* Frameworks/ios/$FWNAME.framework/Headers/
cp -r include-macos/$FWNAME/* Frameworks/macos/$FWNAME.framework/Headers/
echo "Created $FWNAME.framework"