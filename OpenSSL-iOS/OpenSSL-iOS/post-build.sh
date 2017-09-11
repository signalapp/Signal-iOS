#!/bin/bash
#
# post-build.sh
#
# This will copy the `Modules` directory from the framework directory structure to the
# output directory.
# We need to do this as a post-build action because Xcode needs to finish the build before
# this structure is completed.
#
# Levi Brown
# mailto:levigroker@gmail.com
# September 11, 2017
##

IPHONE_DEVICE_BUILD_DIR=${BUILD_DIR}/${CONFIGURATION}-iphoneos
UNIVERSAL_OUTPUTFOLDER=${SRCROOT}/bin

# Copy the framework structure to the universal folder
cp -R "${IPHONE_DEVICE_BUILD_DIR}/${PRODUCT_NAME}.framework/Modules" "${UNIVERSAL_OUTPUTFOLDER}/${PRODUCT_NAME}.framework"
