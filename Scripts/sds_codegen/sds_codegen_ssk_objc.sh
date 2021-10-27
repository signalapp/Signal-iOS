#!/bin/sh

set -e

# The root directory of the repo.
REPO_ROOT=`git rev-parse --show-toplevel`

# We parse Obj-C source files (.m only, not .mm yet) to extract simple class descriptions (class name, base class, property names and types, etc.)
$REPO_ROOT/Scripts/sds_codegen/sds_parse_objc.py --src-path SignalServiceKit/ --swift-bridging-path $REPO_ROOT/Scripts/sds_codegen/sds-includes

$REPO_ROOT/Scripts/sds_codegen/sds_regenerate.sh
