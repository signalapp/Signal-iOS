#!/bin/bash
#
# Autogenerate the framework umbrella header from the headers in the includes directory.
#
# This scans the given INCLUDES_DIR for all header files and uses this information to
# populate the given HEADER_TEMPLATE file, outputting the result to HEADER_DEST.
#
# The template file (HEADER_TEMPLATE) will have the following tags replaced:
#   @GENERATED_CONTENT@ : The list of header includes
#                @DATE@ : The full date when the template was populated
#                @YEAR@ : The four digit year the template was populated
#
# Levi Brown
# mailto:levigroker@gmail.com
# September 8, 2017
##

function fail()
{
    echo "Failed: $@" >&2
    exit 1
}

DEBUG=${DEBUG:-1}
export DEBUG

set -eu
[ $DEBUG -ne 0 ] && set -x

# Fully qualified binaries (_B suffix to prevent collisions)
DATE_B="/bin/date"
RM_B="/bin/rm"
AWK_B="/usr/bin/awk"
SED_B="/usr/bin/sed"
FIND_B="/usr/bin/find"

# The path to the resulting header file
HEADER_DEST=${HEADER_DEST:-""}
if [ "$HEADER_DEST" = "" ]; then
	fail "HEADER_DEST is required."
fi

# The path to the template to populate
HEADER_TEMPLATE=${HEADER_TEMPLATE:-""}
if [ "$HEADER_TEMPLATE" = "" ]; then
	fail "HEADER_TEMPLATE is required."
fi
if [ ! -r "$HEADER_TEMPLATE" ]; then
	fail "\"${HEADER_TEMPLATE}\" file must exist and be readable."
fi

# The directory containing the `openssl` directory which contains the header files to include
INCLUDES_DIR=${INCLUDES_DIR:-""}
if [ "$INCLUDES_DIR" = "" ]; then
	fail "INCLUDES_DIR is required."
fi

# Ensure we do not have stale generated items
$RM_B -f "${HEADER_DEST}"

DATE=$($DATE_B)
YEAR=$($DATE_B "+%Y")
# Generate all the include statements from the headers found in the INCLUDES_DIR
CONTENT=$($FIND_B "${INCLUDES_DIR}" -name "*.h" -print | $SED_B -Ee 's|^.*/(openssl/.+\.h)$|#import <\1>|g')
# Populate the template by replacing the @DATE@,  @YEAR@, and GENERATED_CONTENT@ tags appropriately
$AWK_B -v d="${DATE}" -v y="${YEAR}" -v cont="${CONTENT//$'\n'/\\n}" '{ gsub(/@GENERATED_CONTENT@/,cont); gsub(/@DATE@/,d); gsub(/@YEAR@/,y) }1' "${HEADER_TEMPLATE}" > "${HEADER_DEST}"
