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

FRAMEWORK="openssl.framework"
FRAMEWORK_BIN="${FRAMEWORK}/openssl"

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
UMBRELLA_STATIC_INCLUDES="framework_scripts/static_includes.txt"

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
	echo "$0 build|valid|clean" >&2
	echo "    build   Builds OpenSSL libraries from source." >&2
	echo "    header  Generates macOS and iOS umbrella headers." >&2
	echo "    valid   Validates the frameworks." >&2
	echo "    clean   Removes all build artifacts." >&2
	echo "" >&2
	echo "    ex.: $0 build" >&2
	echo "    ex.: $0 clean" >&2
	echo "" >&2
    exit 1
}

function build()
{
	# Build OpenSSL
	echo "Building OpenSSL ${OPENSSL_VERSION}..."
	source ./build.sh
	echo "Finished building OpenSSL ${OPENSSL_VERSION}"

	header
	
	echo "Build complete. Please follow the steps under \"Building\" in the README.md file to create the macOS and iOS frameworks."
}

function header()
{
	export CONTENT=$(<"${UMBRELLA_STATIC_INCLUDES}")

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
}

function valid()
{
	local VALID=1
	local LIB_BIN="${IOS_BUILD_DIR}/${FRAMEWORK_BIN}"
	
	if [ -r "${LIB_BIN}" ]; then
		# Check expected architectures
		local REZ=$($LIPO_B -info "${LIB_BIN}")
		if [ "$REZ" != "Architectures in the fat file: OpenSSL-iOS/bin/openssl.framework/openssl are: i386 x86_64 armv7 armv7s arm64 " ]; then
			echo "ERROR: Unexpected result from $LIPO_B: \"${REZ}\""
			VALID=0
		else
			echo " GOOD: ${REZ}"
		fi

		# Check for bitcode where expected
		local ARCHS=("arm64" "armv7" "armv7s")
		for ARCH in ${ARCHS[*]}
		do
			local REZ=$($OTOOL_B -arch ${ARCH} -l "${LIB_BIN}" | $GREP_B LLVM)
			if [ "$REZ" == "" ]; then
				echo "ERROR: Did not find bitcode slice for ${ARCH}"
				VALID=0
			else
				echo " GOOD: Found bitcode slice for ${ARCH}"
			fi
		done
	
		# Check for bitcode where not expected
		local ARCHS=("i386")
		for ARCH in ${ARCHS[*]}
		do
			local REZ=$($OTOOL_B -arch ${ARCH} -l "${LIB_BIN}" | $GREP_B LLVM)
			if [ "$REZ" != "" ]; then
				echo "ERROR: Found bitcode slice for ${ARCH}"
				VALID=0
			else
				echo " GOOD: Did not find bitcode slice for ${ARCH}"
			fi
		done
		
		local EXPECTING=("${IOS_BUILD_DIR}/${FRAMEWORK}/Modules/module.modulemap")
		for EXPECT in ${EXPECTING[*]}
		do
			if [ -f "${EXPECT}" ]; then
				echo " GOOD: Found expected file: \"${EXPECT}\""
			else
				echo "ERROR: Did not file expected file: \"${EXPECT}\""
				VALID=0
			fi
		done

	else
		echo "ERROR: \"${LIB_BIN}\" not found. Please be sure it has been built (see README.md)"
		VALID=0
	fi
	
	if [ $VALID -ne 1 ]; then
		fail "Invalid framework"
	fi
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
GREP_B="/usr/bin/grep"
LIPO_B="/usr/bin/lipo"
OTOOL_B="/usr/bin/otool"

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
    header)
		if [[ $# -le 0 ]]; then
			header
		else
			usage
		fi
    ;;
    valid)
		if [[ $# -le 0 ]]; then
			valid
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

