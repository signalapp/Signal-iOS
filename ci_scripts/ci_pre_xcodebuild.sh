#!/bin/sh

set -eux

: "Downloading Metal Toolchain"
xcodebuild -downloadComponent MetalToolchain
