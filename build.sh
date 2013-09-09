#!/bin/bash

# Yay shell scripting! This script builds a static version of
# OpenSSL ${OPENSSL_VERSION} for iOS 5.1 that contains code for armv6, armv7 and i386.

set -x

# Setup paths to stuff we need

OPENSSL_VERSION="1.0.1e"

DEVELOPER="/Applications/Xcode.app/Contents/Developer"

SDK_VERSION="6.1"

IPHONEOS_PLATFORM="${DEVELOPER}/Platforms/iPhoneOS.platform"
IPHONEOS_SDK="${IPHONEOS_PLATFORM}/Developer/SDKs/iPhoneOS${SDK_VERSION}.sdk"
IPHONEOS_GCC="${IPHONEOS_PLATFORM}/Developer/usr/bin/gcc"

IPHONESIMULATOR_PLATFORM="${DEVELOPER}/Platforms/iPhoneSimulator.platform"
IPHONESIMULATOR_SDK="${IPHONESIMULATOR_PLATFORM}/Developer/SDKs/iPhoneSimulator${SDK_VERSION}.sdk"
IPHONESIMULATOR_GCC="${IPHONESIMULATOR_PLATFORM}/Developer/usr/bin/gcc"

# Clean up whatever was left from our previous build

rm -rf include lib
rm -rf "/tmp/openssl-${OPENSSL_VERSION}-*"
rm -rf "/tmp/openssl-${OPENSSL_VERSION}-*.log"

build()
{
   ARCH=$1
   GCC=$2
   SDK=$3
   rm -rf "openssl-${OPENSSL_VERSION}"
   tar xfz "openssl-${OPENSSL_VERSION}.tar.gz"
   pushd .
   cd "openssl-${OPENSSL_VERSION}"
   ./Configure BSD-generic32 --openssldir="/tmp/openssl-${OPENSSL_VERSION}-${ARCH}" &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
   perl -i -pe 's|static volatile sig_atomic_t intr_signal|static volatile int intr_signal|' crypto/ui/ui_openssl.c
   perl -i -pe "s|^CC= gcc|CC= ${GCC} -arch ${ARCH}|g" Makefile
   perl -i -pe "s|^CFLAG= (.*)|CFLAG= -isysroot ${SDK} \$1|g" Makefile
   make &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
   make install &> "/tmp/openssl-${OPENSSL_VERSION}-${ARCH}.log"
   popd
   rm -rf "openssl-${OPENSSL_VERSION}"
}

build "armv7" "${IPHONEOS_GCC}" "${IPHONEOS_SDK}"
build "armv7s" "${IPHONEOS_GCC}" "${IPHONEOS_SDK}"
build "i386" "${IPHONESIMULATOR_GCC}" "${IPHONESIMULATOR_SDK}"

#

mkdir include
cp -r /tmp/openssl-${OPENSSL_VERSION}-i386/include/openssl include/

mkdir lib
lipo \
	"/tmp/openssl-${OPENSSL_VERSION}-armv7/lib/libcrypto.a" \
	"/tmp/openssl-${OPENSSL_VERSION}-armv7s/lib/libcrypto.a" \
	"/tmp/openssl-${OPENSSL_VERSION}-i386/lib/libcrypto.a" \
	-create -output lib/libcrypto.a
lipo \
	"/tmp/openssl-${OPENSSL_VERSION}-armv7/lib/libssl.a" \
	"/tmp/openssl-${OPENSSL_VERSION}-armv7s/lib/libssl.a" \
	"/tmp/openssl-${OPENSSL_VERSION}-i386/lib/libssl.a" \
	-create -output lib/libssl.a

rm -rf "/tmp/openssl-${OPENSSL_VERSION}-*"
rm -rf "/tmp/openssl-${OPENSSL_VERSION}-*.log"

