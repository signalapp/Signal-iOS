#!/bin/sh

set -eux

: "Checking Metal Toolchain"
xcodebuild -showComponent metalToolchain

: "Downloading Metal Toolchain"
xcodebuild -downloadComponent MetalToolchain
