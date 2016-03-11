#!/bin/bash

# Yay shell scripting! This script builds a static version of
# OpenSSL ${OPENSSL_VERSION} for iOS and OSX that contains code for armv6, armv7, armv7s, arm64, i386 and x86_64.

set -x

# Setup paths to stuff we need

OPENSSL_VERSION="1.0.1s"

DEVELOPER=$(xcode-select --print-path)

IPHONEOS_SDK_VERSION=$(xcrun --sdk iphoneos --show-sdk-version)
IPHONEOS_DEPLOYMENT_VERSION="6.0"
IPHONEOS_PLATFORM=$(xcrun --sdk iphoneos --show-sdk-platform-path)
IPHONEOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)

IPHONESIMULATOR_PLATFORM=$(xcrun --sdk iphonesimulator --show-sdk-platform-path)
IPHONESIMULATOR_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

OSX_SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
OSX_DEPLOYMENT_VERSION="10.8"
OSX_PLATFORM=$(xcrun --sdk macosx --show-sdk-platform-path)
OSX_SDK=$(xcrun --sdk macosx --show-sdk-path)

# Clean up whatever was left from our previous build

rm -rf include-ios include-osx lib-ios lib-osx
rm -rf /tmp/openssl-${OPENSSL_VERSION}*

configure() {
    OS=$1
    ARCH=$2
    PLATFORM=$3
    SDK_VERSION=$4
    DEPLOYMENT_VERSION=$5
    
    export CROSS_TOP="${PLATFORM}/Developer"
    export CROSS_SDK="${OS}${SDK_VERSION}.sdk"
    if [ "$ARCH" == "x86_64" ]; then
       ./Configure darwin64-x86_64-cc --openssldir="/tmp/openssl-${OPENSSL_VERSION}-${ARCH}" &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
       sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -arch $ARCH -mios-simulator-version-min=${DEPLOYMENT_VERSION} !" "Makefile"
   else
       ./Configure iphoneos-cross -no-asm --openssldir="/tmp/openssl-${OPENSSL_VERSION}-${ARCH}" &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
       sed -ie "s!^CFLAG=!CFLAG=-mios-simulator-version-min=${DEPLOYMENT_VERSION} !" "Makefile"
       perl -i -pe 's|static volatile sig_atomic_t intr_signal|static volatile int intr_signal|' crypto/ui/ui_openssl.c
   fi
}

build()
{
   ARCH=$1
   SDK=$2
   TYPE=$3

   export BUILD_TOOLS="${DEVELOPER}"
   export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH}"

   mkdir -p "lib-${TYPE}"
   
   rm -rf openssl-${OPENSSL_VERSION}
   tar xfz openssl-${OPENSSL_VERSION}.tar.gz
   pushd .
   cd "openssl-${OPENSSL_VERSION}"

   #fix header for Swift

   sed -ie "s/BIGNUM \*I,/BIGNUM \*i,/g" crypto/rsa/rsa.h

   if [ "$TYPE" == "ios" ]; then
      # IOS
      if [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "i386" ]; then
         configure "iPhoneSimulator" $ARCH ${IPHONESIMULATOR_PLATFORM} ${IPHONEOS_SDK_VERSION} ${IPHONEOS_DEPLOYMENT_VERSION}
      else
         configure "iPhoneOS" $ARCH ${IPHONEOS_PLATFORM} ${IPHONEOS_SDK_VERSION} ${IPHONEOS_DEPLOYMENT_VERSION}
      fi
   elif [ "$TYPE" == "osx" ]; then    
      #OSX
      if [ "$ARCH" == "x86_64" ]; then
         ./Configure darwin64-x86_64-cc --openssldir="/tmp/openssl-${OPENSSL_VERSION}-${ARCH}" &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
         sed -ie "s!^CFLAG=!CFLAG=-isysroot ${SDK} -arch $ARCH -mmacosx-version-min=${OSX_DEPLOYMENT_VERSION} !" "Makefile"
      elif [ "$ARCH" == "i386" ]; then
         ./Configure darwin-i386-cc --openssldir="/tmp/openssl-${OPENSSL_VERSION}-${ARCH}" &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
         sed -ie "s!^CFLAG=!CFLAG=-isysroot ${SDK} -arch $ARCH -mmacosx-version-min=${OSX_DEPLOYMENT_VERSION} !" "Makefile"
      fi
   fi

   make &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
   make install &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
   popd

   # Add arch to library
   if [ -f "lib-${TYPE}/libcrypto.a" ]; then
      xcrun lipo "lib-${TYPE}/libcrypto.a" "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}/lib/libcrypto.a" -create -output "lib-${TYPE}/libcrypto.a"
      xcrun lipo "lib-${TYPE}/libssl.a" "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}/lib/libssl.a" -create -output "lib-${TYPE}/libssl.a"
   else
      cp "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}/lib/libcrypto.a" "lib-${TYPE}/libcrypto.a"
      cp "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}/lib/libssl.a" "lib-${TYPE}/libssl.a"
   fi

   rm -rf "openssl-${OPENSSL_VERSION}"
}

build "i386" "${IPHONESIMULATOR_SDK}" "ios"
build "x86_64" "${IPHONESIMULATOR_SDK}" "ios"
build "armv7" "${IPHONEOS_SDK}" "ios"
build "armv7s" "${IPHONEOS_SDK}" "ios"
build "arm64" "${IPHONEOS_SDK}" "ios"

mkdir -p include-ios
cp -r /tmp/openssl-${OPENSSL_VERSION}-arm64/include/openssl include-ios/

rm -rf /tmp/openssl-${OPENSSL_VERSION}*

build "i386" "${OSX_SDK}" "osx"
build "x86_64" "${OSX_SDK}" "osx"

mkdir -p include-osx
cp -r /tmp/openssl-${OPENSSL_VERSION}-x86_64/include/openssl include-osx/

rm -rf /tmp/openssl-${OPENSSL_VERSION}*
