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

### Configuration

OPENSSL_VERSION="1.0.2l"

# macOS configuration
MAC_HEADER_DEST="OpenSSL-macOS/OpenSSL-macOS/openssl.h"
MAC_HEADER_TEMPLATE="OpenSSL-macOS/OpenSSL-macOS/openssl_umbrella_template.h"
MAC_INCLUDES_DIR="include-macos"
MAC_LIB_DIR="lib-macos"
MAC_BUILD_DIR="OpenSSL-macOS/bin"

# iOS configuration
IOS_HEADER_DEST="OpenSSL-iOS/OpenSSL-iOS/openssl.h"
IOS_HEADER_TEMPLATE="OpenSSL-iOS/OpenSSL-iOS/openssl_umbrella_template.h"
IOS_INCLUDES_DIR="include-ios"
IOS_LIB_DIR="lib-ios"
IOS_BUILD_DIR="OpenSSL-iOS/bin"

UMBRELLA_HEADER_SCRIPT="framework_scripts/create_umbrella_header.sh"

###

function fail()
{
    echo "Failed: $@" >&2
    exit 1
}

function usage()
{
	[[ "$@" = "" ]] || echo "$@" >&2
	echo "Usage:" >&2
	echo "$0 build|clean" >&2
	echo "    build  Builds OpenSSL libraries from source." >&2
	echo "    clean  Removes all build artifacts." >&2
	echo "" >&2
	echo "    ex.: $0 build" >&2
	echo "    ex.: $0 clean" >&2
	echo "" >&2
	echo "    All commands will default to 'dev' environment, and 'latest' tag." >&2
    exit 1
}

function build()
{
	# Build OpenSSL
	echo "Building OpenSSL ${OPENSSL_VERSION}..."
	source ./build.sh
	echo "Finished building OpenSSL ${OPENSSL_VERSION}"

	# Create the macOS umbrella header
	HEADER_DEST="${MAC_HEADER_DEST}"
	HEADER_TEMPLATE="${MAC_HEADER_TEMPLATE}"
	INCLUDES_DIR="${MAC_INCLUDES_DIR}"
	source "${UMBRELLA_HEADER_SCRIPT}"
	echo "Created $HEADER_DEST"

	# Create the iOS umbrella header
	HEADER_DEST="${IOS_HEADER_DEST}"
	HEADER_TEMPLATE="${IOS_HEADER_TEMPLATE}"
	INCLUDES_DIR="${IOS_INCLUDES_DIR}"
	source "${UMBRELLA_HEADER_SCRIPT}"
	echo "Created $HEADER_DEST"
	
	echo "Build complete. Please follow the steps under \"Building\" in the README.md file to create the macOS and iOS frameworks."
}

function clean()
{
	echo "Cleaning macOS..."
	set -x
	$RM_B "${MAC_HEADER_DEST}"
	$RM_B -rf "${MAC_INCLUDES_DIR}"
	$RM_B -rf "${MAC_LIB_DIR}"
	$RM_B -rf "${MAC_BUILD_DIR}"
	[ $DEBUG -ne 1 ] && set +x

	echo "Cleaning iOS..."
	set -x
	$RM_B "${IOS_HEADER_DEST}"
	$RM_B -rf "${IOS_INCLUDES_DIR}"
	$RM_B -rf "${IOS_LIB_DIR}"
	$RM_B -rf "${IOS_BUILD_DIR}"
	[ $DEBUG -ne 1 ] && set +x

	echo "Clean complete"
}


DEBUG=${DEBUG:-0}
export DEBUG

set -eu
[ $DEBUG -ne 0 ] && set -x

# Fully qualified binaries (_B suffix to prevent collisions)
RM_B="/bin/rm"

if [[ $# -eq 0 ]]; then
	usage
fi

command="$1"
shift
case $command in
    build)
		if [[ $# -le 0 ]]; then
			build
		else
			usage
		fi
    ;;
    clean)
		if [[ $# -le 0 ]]; then
			clean
		else
			usage
		fi
    ;;
    *)
		# Unknown option
		usage
    ;;
esac

