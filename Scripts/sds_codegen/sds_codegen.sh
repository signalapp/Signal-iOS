#!/bin/sh

set -eux

# When parsing Obj-c source files, we need to be able to import type
# definitions for all types we use, otherwise clang will treat them
# as `long *`.
#
# This script enumerates all swift files in our codebase (including our Pods)
# and generates fake Obj-c headers (.h) that @interface and @protocol
# stubs for each swift class.  This is analogous to a very simplified
# version of the "-Swift.h" files used by Swift for bridging.
Scripts/sds_codegen/sds_parse_swift_bridging.py --src-path  . --swift-bridging-path Scripts/sds_codegen/sds-includes

# We parse Obj-C source files (.m only, not .mm yet) to extract simple class descriptions (class name, base class, property names and types, etc.)
Scripts/sds_codegen/sds_parse_objc.py --src-path SignalServiceKit/ --swift-bridging-path Scripts/sds_codegen/sds-includes

Scripts/sds_codegen/sds_regenerate.sh

# lint & reformat generated sources
find SignalServiceKit -type f -exec grep --quiet --fixed-strings '// --- CODE GENERATION MARKER' {} \; -print0 | xargs -0 Scripts/precommit.py
