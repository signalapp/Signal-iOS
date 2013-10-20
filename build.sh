#!/bin/bash

# Yay shell scripting! This script builds a static version of
# OpenSSL ${OPENSSL_VERSION} for iOS and OSX that contains code for armv6, armv7, armv7s, arm64, i386 and x86_64.

set -x

# Setup paths to stuff we need

OPENSSL_VERSION="1.0.1e"

DEVELOPER="/Applications/Xcode.app/Contents/Developer"

IOS_SDK_VERSION="7.0"
OSX_SDK_VERSION="10.8"

IPHONEOS_PLATFORM="${DEVELOPER}/Platforms/iPhoneOS.platform"
IPHONEOS_SDK="${IPHONEOS_PLATFORM}/Developer/SDKs/iPhoneOS${IOS_SDK_VERSION}.sdk"

IPHONESIMULATOR_PLATFORM="${DEVELOPER}/Platforms/iPhoneSimulator.platform"
IPHONESIMULATOR_SDK="${IPHONESIMULATOR_PLATFORM}/Developer/SDKs/iPhoneSimulator${IOS_SDK_VERSION}.sdk"

OSX_PLATFORM="${DEVELOPER}/Platforms/MacOSX.platform"
OSX_SDK="${OSX_PLATFORM}/Developer/SDKs/MacOSX${OSX_SDK_VERSION}.sdk"

# Clean up whatever was left from our previous build

rm -rf include-ios include-osx lib-ios lib-osx
rm -rf "/tmp/openssl-${OPENSSL_VERSION}-*"
rm -rf "/tmp/openssl-${OPENSSL_VERSION}-*.log"

build()
{
   ARCH=$1
   SDK=$2
   TYPE=$3

   export BUILD_TOOLS="${DEVELOPER}"
   export CC="${BUILD_TOOLS}/usr/bin/gcc -arch ${ARCH}"

   mkdir -p "lib-${TYPE}"

   rm -rf "openssl-${OPENSSL_VERSION}"
   tar xfz "openssl-${OPENSSL_VERSION}.tar.gz"
   pushd .
   cd "openssl-${OPENSSL_VERSION}"
   if [ "$TYPE" == "ios" ]; then
      # IOS
      if [ "$ARCH" == "x86_64" ]; then
         # Simulator
         ./Configure darwin64-x86_64-cc --openssldir="/tmp/openssl-${OPENSSL_VERSION}-${ARCH}" &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
         perl -i -pe "s|^CFLAG= (.*)|CFLAG= -isysroot ${SDK} \$1|g" Makefile
      elif [ "$ARCH" == "i386" ]; then
         # Simulator
         export CROSS_TOP="${IPHONESIMULATOR_PLATFORM}/Developer"
         export CROSS_SDK="iPhoneSimulator${IOS_SDK_VERSION}.sdk"
         ./Configure iphoneos-cross --openssldir="/tmp/openssl-${OPENSSL_VERSION}-${ARCH}" &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
         sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=7.0 !" "Makefile"
      else
         # iOS
         export CROSS_TOP="${IPHONEOS_PLATFORM}/Developer"
         export CROSS_SDK="iPhoneOS${IOS_SDK_VERSION}.sdk"
         ./Configure iphoneos-cross --openssldir="/tmp/openssl-${OPENSSL_VERSION}-${ARCH}" &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
         perl -i -pe 's|static volatile sig_atomic_t intr_signal|static volatile int intr_signal|' crypto/ui/ui_openssl.c
         sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=7.0 !" "Makefile"
      fi
   else
      #OSX
      if [ "$ARCH" == "x86_64" ]; then
         ./Configure darwin64-x86_64-cc --openssldir="/tmp/openssl-${OPENSSL_VERSION}-${ARCH}" &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
         perl -i -pe "s|^CFLAG= (.*)|CFLAG= -isysroot ${SDK} \$1|g" Makefile
      elif [ "$ARCH" == "i386" ]; then
         ./Configure darwin-i386-cc --openssldir="/tmp/openssl-${OPENSSL_VERSION}-${ARCH}" &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
         perl -i -pe "s|^CFLAG= (.*)|CFLAG= -isysroot ${SDK} \$1|g" Makefile
      fi
   fi

   make &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
   make install &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
   popd
   rm -rf "openssl-${OPENSSL_VERSION}"

   # Add arch to library
   if [ -f "lib-${TYPE}/libcrypto.a" ]; then
      lipo "lib-${TYPE}/libcrypto.a" "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}/lib/libcrypto.a" -create -output "lib-${TYPE}/libcrypto.a"
      lipo "lib-${TYPE}/libssl.a" "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}/lib/libssl.a" -create -output "lib-${TYPE}/libssl.a"
   else
      cp "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}/lib/libcrypto.a" "lib-${TYPE}/libcrypto.a"
      cp "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}/lib/libssl.a" "lib-${TYPE}/libssl.a"
   fi
}

build "armv7" "${IPHONEOS_SDK}" "ios"
build "armv7s" "${IPHONEOS_SDK}" "ios"
build "arm64" "${IPHONEOS_SDK}" "ios"
build "i386" "${IPHONESIMULATOR_SDK}" "ios"
build "x86_64" "${IPHONESIMULATOR_SDK}" "ios"

mkdir -p include-ios
cp -r /tmp/openssl-${OPENSSL_VERSION}-i386/include/openssl include-ios/

build "i386" "${OSX_SDK}" "osx"
build "x86_64" "${OSX_SDK}" "osx"

mkdir -p include-osx
cp -r /tmp/openssl-${OPENSSL_VERSION}-i386/include/openssl include-osx/

rm -rf "/tmp/openssl-${OPENSSL_VERSION}-*"
rm -rf "/tmp/openssl-${OPENSSL_VERSION}-*.log"

