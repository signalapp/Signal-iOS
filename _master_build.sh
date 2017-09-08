#!/bin/bash
#
# Master build script
#
# This will:
#   1. Build OpenSSL libraries for macOS and iOS using the `build.sh`
#   2. Generate the `openssl.h` umbrella header for macOS and iOS based on the contents of
#      the `include-macos` and `include-ios` directories.
#
# Levi Brown
# mailto:levigroker@gmail.com
# September 8, 2017
##

OPENSSL_VERSION="1.0.2l"

function fail()
{
    echo "Failed: $@" >&2
    exit 1
}

DEBUG=${DEBUG:-0}
export DEBUG

set -eu
[ $DEBUG -ne 0 ] && set -x

# Build OpenSSL
source ./build.sh

# Create the macOS umbrella header
HEADER_DEST="OpenSSL-macOS/OpenSSL-macOS/openssl.h"
HEADER_TEMPLATE="OpenSSL-macOS/OpenSSL-macOS/openssl_umbrella_template.h"
INCLUDES_DIR="include-macos"
source "framework_scripts/create_umbrella_header.sh"
echo "Created $HEADER_DEST"

# Create the iOS umbrella header
HEADER_DEST="OpenSSL-iOS/OpenSSL-iOS/openssl.h"
HEADER_TEMPLATE="OpenSSL-iOS/OpenSSL-iOS/openssl_umbrella_template.h"
INCLUDES_DIR="include-ios"
source "framework_scripts/create_umbrella_header.sh"
echo "Created $HEADER_DEST"
