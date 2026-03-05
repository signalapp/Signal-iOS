#!/bin/sh

set -eux

: "Checking Metal Toolchain"
xcodebuild -showComponent metalToolchain

: "Downloading Metal Toolchain"
xcodebuild -downloadComponent metalToolchain -exportPath ./build_assets/

: "Installing Metal Toolchain"
xcodebuild -importComponent metalToolchain -importPath ./build_assets/*.exportedBundle
