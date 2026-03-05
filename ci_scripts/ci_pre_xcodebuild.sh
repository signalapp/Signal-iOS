#!/bin/sh

set -eux

: "Checking Metal Toolchain"
xcodebuild -showComponent metalToolchain

: "Checking Metal version"
xcrun metal --version

: "Downloading Metal Toolchain"
xcodebuild -downloadComponent MetalToolchain
