#!/bin/sh

set -eux

if [ "${CI_WORKFLOW-}" = "Nightly (Xcode 26)" ]; then
    : "Downloading Metal Toolchain for Xcode 26"
    xcodebuild -downloadComponent MetalToolchain
fi
